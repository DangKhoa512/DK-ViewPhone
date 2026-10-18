// GPL-2.0-only. Offline dashboard around the bundled, unmodified noVNC client.
import RFB from './novnc/core/rfb.js';

const $ = id => document.getElementById(id);
const pageHost = location.hostname;
const devicePort = Number(document.body?.dataset?.rfbPort) || 5901;
const secure = location.protocol === 'https:';
const loopbackPage = ['127.0.0.1', 'localhost', '::1'].includes(pageHost);
const retryDelay = attempt => Math.min(2 ** attempt, 16) * 1000;

function privateIPv4(host) {
    const parts = String(host).trim().split('.').map(Number);
    if (parts.length !== 4 || parts.some((value, index) =>
        !Number.isInteger(value) || value < 0 || value > 255 || (index === 0 && value === 0))) return false;
    return parts[0] === 10 || parts[0] === 127 ||
        (parts[0] === 192 && parts[1] === 168) ||
        (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31);
}

function socketURL(device) {
    if (device.websocket_url) return device.websocket_url;
    const host = device.connection_mode === 'usb' ? '127.0.0.1' : device.host;
    return `${secure ? 'wss' : 'ws'}://${host}:${device.vnc_port}/websockify`;
}

function trackScreenAspect(target, surface) {
    if (typeof MutationObserver !== 'function' || !target || !surface) return;
    target.__dkAspectObserver?.disconnect();
    if (target.__dkAspectResize && typeof window !== 'undefined')
        window.removeEventListener('resize', target.__dkAspectResize);
    let ratio = 9 / 16;
    const fitFocusSurface = () => {
        if (!surface.classList.contains('focus-workspace')) return;
        const panel = surface.parentElement;
        const rail = panel?.querySelector('.focus-toolbar');
        const header = panel?.querySelector('.focus-header');
        if (!panel || !rail || !header) return;
        const maxWidth = Math.max(180, panel.clientWidth - rail.offsetWidth - 18);
        const maxHeight = Math.max(260, panel.clientHeight - header.offsetHeight - 18);
        const width = Math.min(maxWidth, maxHeight * ratio);
        const height = width / ratio;
        panel.style.setProperty('--focus-screen-width', `${Math.floor(width)}px`);
        surface.style.width = `${Math.floor(width)}px`;
        surface.style.height = `${Math.floor(height)}px`;
    };
    const update = () => {
        const canvas = target.querySelector('canvas');
        const width = Number(canvas?.width) || 0;
        const height = Number(canvas?.height) || 0;
        if (width > 0 && height > 0) {
            ratio = width / height;
            surface.style.setProperty('--screen-ratio', `${width} / ${height}`);
            surface.classList.add('screen-ready');
        } else {
            surface.style.removeProperty('--screen-ratio');
            surface.classList.remove('screen-ready');
        }
        fitFocusSurface();
    };
    const observer = new MutationObserver(update);
    observer.observe(target, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['width', 'height'],
    });
    target.__dkAspectObserver = observer;
    target.__dkAspectResize = surface.classList.contains('focus-workspace') ? fitFocusSurface : null;
    if (target.__dkAspectResize && typeof window !== 'undefined')
        window.addEventListener('resize', target.__dkAspectResize);
    update();
}

class ManagedRfbSession {
    constructor(options) {
        Object.assign(this, {
            role: 'preview', viewOnly: true, autoReconnect: true, scaleViewport: true,
            password: null, desired: false, paused: false, retries: 0, rfb: null,
            retryTimer: null, connectTimer: null, state: 'idle',
            onState: () => {}, onCredentials: () => {}, onRelease: () => {},
            onDesktopName: () => {},
        }, options);
    }
    setState(state, detail = '') {
        this.state = state;
        this.onState(state, detail);
    }
    requestStart() {
        this.desired = true;
        this.paused = false;
        this.start();
    }
    start() {
        if (!this.desired || this.paused || this.rfb) return;
        this.clearTimers();
        this.target.replaceChildren();
        this.setState('connecting');
        const current = new RFB(this.target, this.url(), {
            credentials: this.password === null ? {} : {password: this.password},
            shared: true,
        });
        this.rfb = current;
        current.viewOnly = this.viewOnly;
        current.scaleViewport = this.scaleViewport;
        current.resizeSession = false;
        current.background = this.role === 'focus' ? '#111c2c' : '#dfe7f1';
        if ('qualityLevel' in current) current.qualityLevel = this.role === 'focus' ? 8 : 3;
        if ('compressionLevel' in current) current.compressionLevel = this.role === 'focus' ? 2 : 6;
        this.connectTimer = setTimeout(() => {
            if (current !== this.rfb) return;
            this.rfb = null;
            current.disconnect();
            this.scheduleRetry('Hết thời gian kết nối');
        }, 15000);
        current.addEventListener('credentialsrequired', () => {
            if (current !== this.rfb) return;
            clearTimeout(this.connectTimer);
            this.connectTimer = null;
            this.setState('auth');
            this.onCredentials({
                submit: value => {
                    this.password = value;
                    if (current === this.rfb && this.desired) {
                        this.setState('connecting');
                        current.sendCredentials({password: value});
                    }
                },
                cancel: () => this.disconnect(),
            });
        });
        current.addEventListener('connect', () => {
            if (current !== this.rfb) return;
            clearTimeout(this.connectTimer);
            this.connectTimer = null;
            this.retries = 0;
            this.setState('online');
            if (this.role === 'focus') current.focus();
        });
        current.addEventListener('desktopname', event => {
            if (current === this.rfb) this.onDesktopName(event.detail?.name || '');
        });
        current.addEventListener('securityfailure', () => {
            if (current !== this.rfb) return;
            this.password = null;
            this.desired = false;
            this.clearTimers();
            this.rfb = null;
            current.disconnect();
            this.setState('error', 'Sai mật khẩu');
            this.onRelease(this);
        });
        current.addEventListener('disconnect', () => {
            if (current !== this.rfb) return;
            this.rfb = null;
            clearTimeout(this.connectTimer);
            this.connectTimer = null;
            this.target.replaceChildren();
            if (this.desired && !this.paused && this.autoReconnect) this.scheduleRetry();
            else {
                this.setState(this.paused ? 'waiting' : 'offline', this.paused ? 'Đang tạm dừng' : '');
                this.onRelease(this);
            }
        });
    }
    scheduleRetry(detail = '') {
        clearTimeout(this.retryTimer);
        this.retryTimer = null;
        this.onRelease(this);
        if (!this.desired || this.paused || !this.autoReconnect || this.retries >= 5) {
            this.desired = false;
            this.setState('offline', detail || 'Đã ngắt');
            return;
        }
        const delay = retryDelay(++this.retries);
        this.setState('retry', detail || `Thử lại sau ${delay / 1000}s`);
        this.retryTimer = setTimeout(() => {
            this.retryTimer = null;
            if (this.requestSlot) this.requestSlot(this);
            else this.start();
        }, delay);
    }
    pause(detail = 'Đang tạm dừng') {
        if (!this.desired) return;
        this.paused = true;
        this.clearTimers();
        const current = this.rfb;
        this.rfb = null;
        if (current) current.disconnect();
        this.target.replaceChildren();
        this.setState('waiting', detail);
        this.onRelease(this);
    }
    resume() {
        if (!this.desired) return;
        this.paused = false;
        if (this.requestSlot) this.requestSlot(this);
        else this.start();
    }
    disconnect() {
        this.desired = false;
        this.paused = false;
        this.retries = 0;
        this.password = null;
        this.clearTimers();
        const current = this.rfb;
        this.rfb = null;
        if (current) current.disconnect();
        this.target.replaceChildren();
        this.setState('offline');
        this.onRelease(this);
    }
    setViewOnly(value) {
        this.viewOnly = !!value;
        if (this.rfb) this.rfb.viewOnly = this.viewOnly;
    }
    setScale(value) {
        this.scaleViewport = !!value;
        if (this.rfb) this.rfb.scaleViewport = this.scaleViewport;
    }
    clearTimers() {
        clearTimeout(this.retryTimer);
        clearTimeout(this.connectTimer);
        this.retryTimer = this.connectTimer = null;
    }
    dispose() { this.disconnect(); }
}

// Exposes deterministic helpers to the repository's no-DOM contract test.
if (typeof window !== 'undefined') {
    window.__DK_VIEWPHONE_TEST__ = {ManagedRfbSession, privateIPv4, retryDelay, socketURL};
}

function initDashboard() {
    const STORAGE_KEY = 'dk-viewphone-devices-v1';
    const PREFS_KEY = 'dk-viewphone-multi-prefs-v1';
    const STATES = {
        idle: 'Chưa kết nối', waiting: 'Đang chờ', connecting: 'Đang kết nối',
        online: 'Online', retry: 'Chờ kết nối lại', auth: 'Cần mật khẩu',
        offline: 'Offline', error: 'Lỗi',
    };
    const makeId = () => globalThis.crypto?.randomUUID?.() ||
        `device-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const cleanDevice = raw => ({
        device_id: String(raw.device_id || makeId()),
        name: String(raw.name || 'iPhone').slice(0, 60),
        host: String(raw.host || ''),
        vnc_port: Math.min(65535, Math.max(1, Number(raw.vnc_port) || 5901)),
        websocket_url: String(raw.websocket_url || ''),
        connection_mode: raw.connection_mode === 'usb' ? 'usb' : 'lan',
        auto_reconnect: raw.auto_reconnect !== false,
        demo: raw.demo === true,
    });
    const currentDevice = cleanDevice({
        device_id: 'current-iphone', name: 'iPhone hiện tại',
        host: loopbackPage ? '127.0.0.1' : pageHost, vnc_port: devicePort,
        connection_mode: loopbackPage ? 'usb' : 'lan', auto_reconnect: true,
    });
    let devices = [];
    let seededCurrent = false;
    try {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
        devices = Array.isArray(saved) ? saved.map(cleanDevice) : [];
    } catch {}
    if (!devices.length && (loopbackPage || privateIPv4(pageHost))) {
        devices = [currentDevice];
        seededCurrent = true;
    }
    let prefs = {columns: 3, limit: 6};
    try { prefs = {...prefs, ...JSON.parse(localStorage.getItem(PREFS_KEY) || '{}')}; } catch {}
    prefs.columns = [2, 3, 4, 5].includes(Number(prefs.columns)) ? Number(prefs.columns) : 3;
    prefs.limit = Math.min(12, Math.max(1, Number(prefs.limit) || 6));

    let pendingLogin = null;
    const loginQueue = [];
    let selectedDeviceId = '';

    function setMessage(text) { $('dashboardMessage').textContent = text; }
    function saveDevices() {
        const safe = devices.map(({connection_status, ...device}) => device);
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(safe)); }
        catch { setMessage('Trình duyệt không cho phép lưu danh sách thiết bị.'); }
    }
    function savePrefs() {
        try { localStorage.setItem(PREFS_KEY, JSON.stringify(prefs)); } catch {}
    }
    function validateDevice(device, editingId = '') {
        if (!device.name.trim()) throw new Error('Tên thiết bị không được để trống.');
        if (device.connection_mode === 'lan' && !privateIPv4(device.host))
            throw new Error('LAN chỉ chấp nhận IPv4 nội bộ hoặc loopback.');
        if (device.connection_mode === 'usb') device.host = '127.0.0.1';
        if (device.vnc_port < 1 || device.vnc_port > 65535)
            throw new Error('Cổng VNC phải nằm trong 1–65535.');
        if (device.connection_mode === 'usb' && devices.some(item =>
            item.device_id !== editingId && item.connection_mode === 'usb' && item.vnc_port === device.vnc_port))
            throw new Error('Mỗi iPhone USB cần một cổng forward riêng trên PC.');
        if (device.websocket_url) {
            let url;
            try { url = new URL(device.websocket_url); }
            catch { throw new Error('WebSocket URL không hợp lệ.'); }
            if (!['ws:', 'wss:'].includes(url.protocol) || url.username || url.password)
                throw new Error('URL phải dùng ws/wss và không được chứa thông tin đăng nhập.');
            if (!privateIPv4(url.hostname) && !['localhost', '[::1]', '::1'].includes(url.hostname))
                throw new Error('WebSocket chỉ được trỏ tới địa chỉ LAN hoặc loopback.');
            if (secure && url.protocol !== 'wss:')
                throw new Error('Trang HTTPS chỉ có thể kết nối bằng WSS.');
        }
        return device;
    }
    function requestCredentials(device, request) {
        loginQueue.push({...request, title: device.name});
        activateNextLogin();
    }
    function activateNextLogin() {
        if (pendingLogin || !loginQueue.length) return;
        pendingLogin = loginQueue.shift();
        $('loginTitle').textContent = `Kết nối ${pendingLogin.title}`;
        $('login').showModal();
        $('password').focus();
    }
    function finishLogin(cancelled) {
        const request = pendingLogin;
        pendingLogin = null;
        const value = $('password').value;
        $('password').value = '';
        if ($('login').open) $('login').close();
        if (request) cancelled ? request.cancel() : request.submit(value);
        activateNextLogin();
    }

    class PreviewSession extends ManagedRfbSession {
        constructor(manager, device, card) {
            const screen = card.querySelector('.card-screen');
            super({
                role: 'preview', target: screen, url: () => socketURL(device),
                viewOnly: true, autoReconnect: device.auto_reconnect,
            });
            this.manager = manager;
            this.device = device;
            this.card = card;
            this.placeholder = card.querySelector('.card-placeholder');
            trackScreenAspect(screen, card.querySelector('.card-preview'));
            this.requestSlot = () => manager.requestPreview(this);
            this.onCredentials = request => requestCredentials(device, request);
            this.onRelease = () => manager.release(this);
            this.onState = (state, detail) => {
                device.connection_status = state;
                card.dataset.state = state;
                const layer = card.querySelector('.card-state-layer');
                layer.className = `card-state-layer ${state}`;
                layer.querySelector('span').textContent = detail || STATES[state] || state;
                this.placeholder.hidden = state === 'online';
                syncCardButtons(card, this);
                manager.updateSummary();
                applyFilter();
            };
        }
        requestConnect() {
            this.desired = true;
            this.paused = false;
            this.manager.requestPreview(this);
        }
    }

    class DashboardManager {
        constructor() {
            this.sessions = new Map();
            this.cards = new Map();
            this.visible = new Set();
            this.pending = new Set();
            this.observer = null;
            this.focusSession = null;
            this.focusDeviceId = '';
            this.focusPaused = null;
        }
        limit() { return prefs.limit; }
        activeCount() {
            let count = [...this.sessions.values()].filter(session => !!session.rfb).length;
            if (this.focusSession?.rfb) count++;
            return count;
        }
        liveCount() {
            let count = [...this.sessions.values()].filter(session => session.state === 'online').length;
            if (this.focusSession?.state === 'online') count++;
            return count;
        }
        isDeviceOnline(id) {
            return this.sessions.get(id)?.state === 'online' ||
                (this.focusDeviceId === id && this.focusSession?.state === 'online');
        }
        isVisible(id) {
            if (this.visible.has(id)) return true;
            const card = this.cards.get(id);
            if (!card || card.classList.contains('hidden-card')) return false;
            const rect = card.getBoundingClientRect();
            return rect.bottom > 0 && rect.top < (window.innerHeight || document.documentElement.clientHeight);
        }
        requestPreview(session) {
            if (!session.desired || session.paused) return;
            const id = session.device.device_id;
            if (!this.isVisible(id)) {
                this.pending.add(id);
                session.setState('waiting', 'Chờ card vào vùng nhìn');
                return;
            }
            if (this.activeCount() >= this.limit()) {
                this.pending.add(id);
                session.setState('waiting', `Chờ giới hạn ${this.limit()} live`);
                return;
            }
            this.pending.delete(id);
            session.start();
        }
        reserveFocusSlot(deviceId) {
            if (this.activeCount() < this.limit()) return;
            const preferred = this.sessions.get(deviceId);
            const candidate = preferred?.rfb ? preferred :
                [...this.sessions.values()].find(session => session.rfb);
            if (candidate) {
                this.focusPaused = candidate;
                candidate.pause('Nhường tài nguyên cho điều khiển');
            }
        }
        enforceLimit() {
            const candidates = [...this.sessions.values()].filter(session => session.rfb);
            while (this.activeCount() > this.limit() && candidates.length) {
                const session = candidates.pop();
                this.pending.add(session.device.device_id);
                session.pause(`Chờ giới hạn ${this.limit()} live`);
            }
        }
        release() {
            setTimeout(() => this.pump(), 0);
            this.updateSummary();
        }
        pump() {
            for (const id of [...this.pending]) {
                const session = this.sessions.get(id);
                if (!session || !session.desired) {
                    this.pending.delete(id);
                    continue;
                }
                if (this.activeCount() >= this.limit()) break;
                if (this.isVisible(id) && !session.paused) {
                    this.pending.delete(id);
                    session.start();
                }
            }
        }
        observe(card, id) {
            this.cards.set(id, card);
            if (typeof IntersectionObserver !== 'function') {
                this.visible.add(id);
                return;
            }
            if (!this.observer) {
                this.observer = new IntersectionObserver(entries => {
                    for (const entry of entries) {
                        const key = entry.target.dataset.id;
                        const session = this.sessions.get(key);
                        if (entry.isIntersecting) {
                            this.visible.add(key);
                            if (session?.desired && session.paused && session !== this.focusPaused) session.resume();
                        } else {
                            this.visible.delete(key);
                            if (session?.desired && session.rfb && key !== this.focusDeviceId)
                                session.pause('Ngoài vùng nhìn');
                        }
                    }
                    this.pump();
                }, {rootMargin: '180px'});
            }
            this.observer.observe(card);
        }
        closeFocus(resumePreview = true) {
            const previousId = this.focusDeviceId;
            if (this.focusSession) this.focusSession.dispose();
            this.focusSession = null;
            this.focusDeviceId = '';
            if (resumePreview && this.focusPaused) {
                const paused = this.focusPaused;
                this.focusPaused = null;
                if (paused.desired && this.isVisible(paused.device.device_id)) paused.resume();
            } else this.focusPaused = null;
            if (previousId) this.cards.get(previousId)?.classList.remove('controlling');
            this.updateSummary();
        }
        disconnectAll() {
            this.closeFocus(false);
            for (const session of this.sessions.values()) session.disconnect();
            this.pending.clear();
            this.updateSummary();
        }
        desiredIds() {
            return [...this.sessions.values()].filter(session => session.desired)
                .map(session => session.device.device_id);
        }
        disposeAll() {
            this.closeFocus(false);
            if (this.observer) this.observer.disconnect();
            for (const session of this.sessions.values()) session.dispose();
            this.sessions.clear();
            this.cards.clear();
            this.visible.clear();
            this.pending.clear();
        }
        updateSummary() {
            const online = devices.filter(device => this.isDeviceOnline(device.device_id)).length;
            const live = this.liveCount();
            $('onlineCount').textContent = String(online);
            $('liveCount').textContent = `${live} / ${this.limit()}`;
            $('disconnectAll').disabled = ![...this.sessions.values()].some(session => session.desired) &&
                !this.focusSession;
            document.querySelector('.online-stat').classList.toggle('active', online > 0);
            const modes = new Set(devices.map(device => device.connection_mode.toUpperCase()));
            const modeText = modes.size ? [...modes].join(' + ') : 'LAN / USB';
            $('modeSummary').textContent = window.dkDesktop ? `DESKTOP · ${modeText}` : modeText;
        }
    }

    let manager = new DashboardManager();

    function syncCardButtons(card, session) {
        card.querySelector('.connect-device').disabled = session.desired;
        card.querySelector('.disconnect-device').disabled = !session.desired;
    }
    function selectDevice(id) {
        selectedDeviceId = id;
        for (const [cardId, card] of manager.cards)
            card.classList.toggle('selected', cardId === id);
    }
    function endpointLabel(device) {
        const host = device.connection_mode === 'usb' ? '127.0.0.1' : device.host;
        return `${host}:${device.vnc_port}`;
    }
    function cardFor(device) {
        const card = document.createElement('article');
        card.className = 'device-card';
        card.dataset.id = device.device_id;
        card.innerHTML = '<div class="card-top"><span class="device-slot" aria-hidden="true"></span><input class="card-select" type="checkbox" aria-label="Chọn thiết bị"><div class="card-title"><strong></strong><span></span></div><div class="card-menu"><button class="edit-device" title="Sửa thiết bị">Sửa</button><button class="delete-device" title="Xóa thiết bị">Xóa</button></div></div><button class="card-preview" title="Bấm đúp để điều khiển"><div class="card-screen"></div><div class="card-placeholder"><div><div class="empty-phone"></div><strong>Chưa có Live View</strong><span>Nhấn Kết nối để bắt đầu preview</span></div></div><div class="card-state-layer idle"><i></i><span>Chưa kết nối</span></div><span class="focus-badge" hidden>ĐANG ĐIỀU KHIỂN</span></button><div class="card-bottom"><span class="transport-chip"></span><button class="connect-device">Kết nối</button><button class="disconnect-device" disabled>Ngắt</button><button class="open-device">Điều khiển</button></div>';
        card.querySelector('.card-title strong').textContent = device.name;
        card.querySelector('.card-title span').textContent = endpointLabel(device);
        card.querySelector('.transport-chip').textContent = device.connection_mode.toUpperCase();
        const session = new PreviewSession(manager, device, card);
        manager.sessions.set(device.device_id, session);
        card.addEventListener('click', event => {
            if (!event.target.closest('button,input')) selectDevice(device.device_id);
        });
        card.querySelector('.card-preview').addEventListener('click', () => selectDevice(device.device_id));
        card.querySelector('.card-preview').addEventListener('dblclick', () => openFocus(device.device_id));
        card.querySelector('.connect-device').addEventListener('click', () => session.requestConnect());
        card.querySelector('.disconnect-device').addEventListener('click', () => session.disconnect());
        card.querySelector('.open-device').addEventListener('click', () => openFocus(device.device_id));
        card.querySelector('.edit-device').addEventListener('click', () => openEditor(device.device_id));
        card.querySelector('.delete-device').addEventListener('click', () => {
            if (manager.focusDeviceId === device.device_id) closeFocus();
            session.dispose();
            devices = devices.filter(item => item.device_id !== device.device_id);
            saveDevices();
            renderAll();
        });
        return card;
    }
    function renderAll(resumeIds = []) {
        manager.disposeAll();
        manager = new DashboardManager();
        $('deviceGrid').replaceChildren();
        for (const device of devices) {
            const card = cardFor(device);
            $('deviceGrid').append(card);
            manager.observe(card, device.device_id);
        }
        populateFocusSwitcher();
        applyFilter();
        manager.updateSummary();
        setTimeout(() => {
            for (const id of resumeIds) manager.sessions.get(id)?.requestConnect();
        }, 0);
    }
    function applyFilter() {
        const query = $('deviceSearch').value.trim().toLowerCase();
        const filter = $('deviceFilter').value;
        let shown = 0;
        for (const device of devices) {
            const card = manager.cards.get(device.device_id);
            if (!card) continue;
            const online = manager.isDeviceOnline(device.device_id);
            const matchesText = !query || device.name.toLowerCase().includes(query) ||
                device.host.includes(query) || String(device.vnc_port).includes(query);
            const matchesState = filter === 'all' || (filter === 'online' && online) ||
                (filter === 'offline' && !online);
            const matches = matchesText && matchesState;
            card.classList.toggle('hidden-card', !matches);
            if (matches) shown++;
        }
        $('noDevices').hidden = shown !== 0;
        $('visibleCount').textContent = `${shown} máy`;
    }
    function selectedSessions() {
        return [...manager.cards.values()]
            .filter(card => card.querySelector('.card-select').checked &&
                !card.classList.contains('hidden-card'))
            .map(card => manager.sessions.get(card.dataset.id))
            .filter(Boolean);
    }
    function openEditor(id = '') {
        const device = devices.find(item => item.device_id === id);
        $('deviceEditorTitle').textContent = device ? 'Sửa thiết bị' : 'Thêm thiết bị';
        $('deviceId').value = device?.device_id || '';
        $('deviceLabel').value = device?.name || `iPhone ${String(devices.length + 1).padStart(2, '0')}`;
        $('deviceMode').value = device?.connection_mode || 'lan';
        $('deviceHost').value = device?.host || (privateIPv4(pageHost) ? pageHost : '');
        $('deviceVncPort').value = String(device?.vnc_port || 5901);
        $('deviceWebsocket').value = device?.websocket_url || '';
        $('deviceReconnect').checked = device?.auto_reconnect !== false;
        $('deviceFormError').textContent = '';
        $('deviceEditor').showModal();
    }
    function populateFocusSwitcher() {
        const value = manager.focusDeviceId;
        $('focusDevice').replaceChildren(...devices.map(device => {
            const option = document.createElement('option');
            option.value = device.device_id;
            option.textContent = `${device.name} · ${endpointLabel(device)}`;
            return option;
        }));
        if (value) $('focusDevice').value = value;
    }
    function setFocusState(state, detail = '') {
        const status = $('focusStatus');
        status.className = `session-status ${state}`;
        status.querySelector('span').textContent = detail || STATES[state] || state;
        $('focusPlaceholder').hidden = state === 'online';
        $('focusConnect').disabled = ['connecting', 'online', 'auth', 'retry'].includes(state);
        $('focusDisconnect').disabled = ['idle', 'offline', 'error'].includes(state);
        if (state === 'online') $('focusMessage').textContent =
            $('focusViewOnly').checked ? 'Chế độ chỉ xem đang bật.' : 'Sẵn sàng tap, swipe và nhập bàn phím.';
        manager.updateSummary();
        applyFilter();
    }
    function openFocus(id) {
        const device = devices.find(item => item.device_id === id);
        if (!device) return;
        if (manager.focusDeviceId === id && manager.focusSession) {
            $('focusPanel').hidden = false;
            return;
        }
        manager.closeFocus(true);
        manager.focusDeviceId = id;
        manager.reserveFocusSlot(id);
        selectDevice(id);
        $('focusPanel').hidden = false;
        $('dashboard').classList.add('focus-open');
        $('focusName').textContent = device.name;
        $('focusAddress').textContent = `${device.connection_mode.toUpperCase()} · ${endpointLabel(device)}`;
        populateFocusSwitcher();
        $('focusDevice').value = id;
        for (const [cardId, card] of manager.cards) {
            const active = cardId === id;
            card.classList.toggle('controlling', active);
            card.querySelector('.focus-badge').hidden = !active;
        }
        const session = new ManagedRfbSession({
            role: 'focus', target: $('focusScreen'), url: () => socketURL(device),
            viewOnly: $('focusViewOnly').checked, autoReconnect: device.auto_reconnect,
            scaleViewport: $('focusAutoScale').checked,
            onState: setFocusState,
            onCredentials: request => requestCredentials(device, request),
            onRelease: () => manager.release(),
            onDesktopName: name => { if (name) $('focusName').textContent = name; },
        });
        trackScreenAspect($('focusScreen'), $('focusWorkspace'));
        manager.focusSession = session;
        manager.updateSummary();
        setFocusState('connecting');
        session.requestStart();
    }
    function closeFocus() {
        manager.closeFocus(true);
        $('focusPanel').hidden = true;
        $('dashboard').classList.remove('focus-open');
        $('focusScreen').replaceChildren();
        $('focusPlaceholder').hidden = false;
        setMessage('Đã đóng bảng điều khiển. Các preview tiếp tục theo giới hạn live.');
    }
    function moveFocus(step) {
        if (!devices.length) return;
        const current = devices.findIndex(device => device.device_id === manager.focusDeviceId);
        const index = current < 0 ? 0 : (current + step + devices.length) % devices.length;
        openFocus(devices[index].device_id);
    }
    function addDemoDevices() {
        const prefix = privateIPv4(pageHost) ? pageHost.split('.').slice(0, 3).join('.') : '192.168.1';
        const existing = new Set(devices.map(device => device.host));
        let added = 0;
        for (let index = 1; index <= 6; index++) {
            const host = `${prefix}.${200 + index}`;
            if (existing.has(host)) continue;
            devices.push(cleanDevice({
                name: `iPhone Farm ${String(index).padStart(2, '0')}`, host,
                vnc_port: 5901, connection_mode: 'lan', auto_reconnect: true, demo: true,
            }));
            added++;
        }
        saveDevices();
        renderAll();
        setMessage(`Đã thêm ${added} card mẫu offline. Chúng không tự kết nối.`);
    }
    async function scanLAN() {
        if (!window.dkDesktop?.scanLAN) return;
        const button = $('scanLan');
        const original = button.textContent;
        button.disabled = true;
        button.textContent = 'Đang quét…';
        setMessage('Đang quét các cổng 5801/5901 trên mạng LAN riêng…');
        try {
            const result = await window.dkDesktop.scanLAN();
            const found = Array.isArray(result?.devices) ? result.devices : [];
            let added = 0;
            for (const discovered of found) {
                const port = Number(discovered.vnc_port) || 5901;
                const exists = devices.some(device => device.connection_mode === 'lan' &&
                    device.host === discovered.host && device.vnc_port === port);
                if (exists) continue;
                const device = cleanDevice({
                    name: discovered.name || `iPhone ${discovered.host}`,
                    host: discovered.host, vnc_port: port, connection_mode: 'lan',
                    auto_reconnect: true,
                });
                devices.push(device);
                const card = cardFor(device);
                $('deviceGrid').append(card);
                manager.observe(card, device.device_id);
                added++;
            }
            saveDevices();
            populateFocusSwitcher();
            applyFilter();
            manager.updateSummary();
            const subnetText = Array.isArray(result?.subnets) ? result.subnets.join(', ') : 'LAN';
            const webOnly = Array.isArray(result?.web_only) ? result.web_only.length : 0;
            const webOnlyText = webOnly ? `, ${webOnly} máy chỉ mở HTTP` : '';
            setMessage(`Quét ${subnetText}: thấy ${found.length} máy VNC${webOnlyText}, thêm ${added} máy mới trong ${result?.duration_ms || 0} ms.`);
        } catch (error) {
            setMessage(`Không thể quét LAN: ${error?.message || error}`);
        } finally {
            button.disabled = false;
            button.textContent = original;
        }
    }

    $('gridColumns').value = String(prefs.columns);
    $('liveLimit').value = String(prefs.limit);
    $('deviceGrid').className = `device-grid columns-${prefs.columns}`;
    $('transportNotice').textContent = secure
        ? 'HTTPS/WSS đang bật. Chứng chỉ phải được trình duyệt tin cậy cho từng iPhone.'
        : 'HTTP/WS không mã hóa. Chỉ sử dụng trong mạng LAN tin cậy và không mở cổng ra Internet.';
    $('transportNotice').classList.toggle('secure', secure);

    $('addDevice').addEventListener('click', () => openEditor());
    $('emptyAddDevice').addEventListener('click', () => openEditor());
    $('loadDemo').addEventListener('click', addDemoDevices);
    if (window.dkDesktop?.scanLAN) {
        $('scanLan').hidden = false;
        $('scanLan').addEventListener('click', scanLAN);
    }
    $('cancelDevice').addEventListener('click', () => $('deviceEditor').close());
    $('cancelDeviceTop').addEventListener('click', () => $('deviceEditor').close());
    $('deviceForm').addEventListener('submit', event => {
        event.preventDefault();
        try {
            const id = $('deviceId').value;
            const device = validateDevice(cleanDevice({
                device_id: id || makeId(), name: $('deviceLabel').value.trim(),
                connection_mode: $('deviceMode').value, host: $('deviceHost').value.trim(),
                vnc_port: Number($('deviceVncPort').value),
                websocket_url: $('deviceWebsocket').value.trim(),
                auto_reconnect: $('deviceReconnect').checked,
            }), id);
            const resume = manager.desiredIds();
            const index = devices.findIndex(item => item.device_id === id);
            if (index >= 0) devices[index] = device;
            else devices.push(device);
            saveDevices();
            $('deviceEditor').close();
            renderAll(resume);
        } catch (error) { $('deviceFormError').textContent = error.message; }
    });
    $('deviceMode').addEventListener('change', () => {
        if ($('deviceMode').value === 'usb') $('deviceHost').value = '127.0.0.1';
    });
    $('connectSelected').addEventListener('click', () => {
        let sessions = selectedSessions();
        if (!sessions.length && selectedDeviceId) sessions = [manager.sessions.get(selectedDeviceId)].filter(Boolean);
        if (!sessions.length) return setMessage('Hãy chọn ít nhất một thiết bị.');
        for (const session of sessions) session.requestConnect();
    });
    $('disconnectSelected').addEventListener('click', () => {
        let sessions = selectedSessions();
        if (!sessions.length && selectedDeviceId) sessions = [manager.sessions.get(selectedDeviceId)].filter(Boolean);
        if (!sessions.length) return setMessage('Hãy chọn ít nhất một thiết bị.');
        for (const session of sessions) session.disconnect();
    });
    $('disconnectAll').addEventListener('click', () => {
        manager.disconnectAll();
        $('focusPanel').hidden = true;
        $('dashboard').classList.remove('focus-open');
        setMessage('Đã ngắt toàn bộ preview và phiên điều khiển.');
    });
    $('deviceSearch').addEventListener('input', applyFilter);
    $('deviceFilter').addEventListener('change', applyFilter);
    $('gridColumns').addEventListener('change', () => {
        prefs.columns = [2, 3, 4, 5].includes(Number($('gridColumns').value)) ?
            Number($('gridColumns').value) : 3;
        $('deviceGrid').className = `device-grid columns-${prefs.columns}`;
        savePrefs();
    });
    $('liveLimit').addEventListener('change', () => {
        prefs.limit = Math.min(12, Math.max(1, Number($('liveLimit').value) || 6));
        $('liveLimit').value = String(prefs.limit);
        savePrefs();
        manager.enforceLimit();
        manager.pump();
        manager.updateSummary();
    });
    $('closeFocus').addEventListener('click', closeFocus);
    $('focusDevice').addEventListener('change', () => openFocus($('focusDevice').value));
    $('previousDevice').addEventListener('click', () => moveFocus(-1));
    $('nextDevice').addEventListener('click', () => moveFocus(1));
    $('focusConnect').addEventListener('click', () => {
        if (!manager.focusSession) return;
        manager.reserveFocusSlot(manager.focusDeviceId);
        manager.focusSession.requestStart();
    });
    $('focusDisconnect').addEventListener('click', () => manager.focusSession?.disconnect());
    $('focusViewOnly').addEventListener('change', () =>
        manager.focusSession?.setViewOnly($('focusViewOnly').checked));
    $('focusAutoScale').addEventListener('change', () =>
        manager.focusSession?.setScale($('focusAutoScale').checked));
    $('focusFullscreen').addEventListener('click', async () => {
        try {
            if (document.fullscreenElement) await document.exitFullscreen();
            else await $('focusWorkspace').requestFullscreen();
        } catch { $('focusMessage').textContent = 'Trình duyệt không cho phép toàn màn hình.'; }
    });
    $('loginForm').addEventListener('submit', event => {
        event.preventDefault();
        finishLogin(false);
    });
    $('cancelLogin').addEventListener('click', () => finishLogin(true));
    $('login').addEventListener('cancel', event => {
        event.preventDefault();
        finishLogin(true);
    });

    renderAll();
    saveDevices();
    if (seededCurrent) setTimeout(() => manager.sessions.get('current-iphone')?.requestConnect(), 0);
    window.addEventListener('pagehide', () => {
        manager.disposeAll();
        loginQueue.length = 0;
        pendingLogin = null;
    });
}

if (typeof document.querySelector === 'function' && document.querySelector('#deviceGrid')) initDashboard();
