// GPL-2.0-only. Offline wrapper around the bundled, unmodified noVNC client.
import RFB from './novnc/core/rfb.js';
const $ = id => document.getElementById(id);
let rfb = null, password = null, retryTimer = null, retries = 0, manual = true, singleTarget = null;
let pendingLogin = null;
const loginQueue = [];
const pageHost = location.hostname;
const devicePort = Number(document.body.dataset.rfbPort) || 5901;
const secure = location.protocol === 'https:';
const loopbackPage = pageHost === '127.0.0.1' || pageHost === 'localhost' || pageHost === '::1';
$('modeLan').checked = !loopbackPage; $('modeUsb').checked = loopbackPage;
try { const saved = Number(sessionStorage.getItem('dk-usb-vnc-port')); if (saved >= 1 && saved <= 65535) $('usbPort').value = String(saved); } catch {}

function connectionMode() { return $('modeUsb').checked ? 'usb' : 'lan'; }
function endpoint() {
    if (singleTarget) return singleTarget;
    if (connectionMode() === 'usb') {
        const selected = Number($('usbPort').value);
        return { host: '127.0.0.1', port: selected >= 1 && selected <= 65535 ? selected : 5901, mode: 'usb' };
    }
    return { host: pageHost, port: devicePort, mode: 'lan' };
}
function socketURL(target) {
    if (target.websocketUrl) return target.websocketUrl;
    return `${secure ? 'wss' : 'ws'}://${target.host}:${target.port}/websockify`;
}
function updateConnectionUI() {
    const mode = connectionMode(), target = endpoint();
    $('usbPortField').hidden = mode !== 'usb' || !!singleTarget;
    $('address').textContent = mode === 'usb'
        ? `USB · 127.0.0.1:${target.port} → iPhone:5901`
        : `LAN · ${target.host}:${target.port} · Web ${location.port || (secure ? 443 : 80)}`;
    if (mode === 'usb') {
        $('transport').textContent = secure
            ? 'USB + WSS · Cần forward cổng HTTP và VNC; chứng chỉ phải hợp lệ cho 127.0.0.1. Mỗi iPhone dùng cặp cổng PC riêng.'
            : 'USB + WS · Forward cổng HTTP và VNC bằng iproxy/usbmuxd. Mỗi iPhone dùng cặp cổng PC riêng.';
    } else {
        $('transport').textContent = secure
            ? 'LAN qua HTTPS + WSS · Chứng chỉ phải được trình duyệt tin cậy cho từng iPhone.'
            : 'LAN qua HTTP + WS không mã hóa. Chỉ dùng trong LAN tin cậy; không mở cổng ra Internet.';
    }
    $('transport').classList.toggle('secure', secure);
}
function status(text, connected = false) {
    $('state').textContent = text; $('status').classList.toggle('online', connected);
    $('connect').disabled = !!rfb || !!retryTimer;
    $('disconnect').disabled = manual; $('headerDisconnect').disabled = manual;
}
function message(text) { $('message').textContent = text; }

function activateNextLogin() {
    if (pendingLogin || !loginQueue.length) return;
    pendingLogin = loginQueue.shift();
    $('loginTitle').textContent = `Kết nối ${pendingLogin.title || 'iPhone'}`;
    $('login').showModal(); $('password').focus();
}
function requestCredentials(request) { loginQueue.push(request); activateNextLogin(); }
function finishLogin(cancelled) {
    const request = pendingLogin; pendingLogin = null;
    const value = $('password').value; $('password').value = '';
    if ($('login').open) $('login').close();
    if (request) cancelled ? request.cancel() : request.submit(value);
    activateNextLogin();
}

function stop() {
    manual = true; password = null; retries = 0;
    clearTimeout(retryTimer); retryTimer = null;
    const previous = rfb; rfb = null; if (previous) previous.disconnect();
    $('password').value = '';
    $('empty').hidden = false; status('Đã ngắt kết nối');
}
function connect() {
    clearTimeout(retryTimer); retryTimer = null;
    if (manual) return;
    const target = endpoint();
    const current = new RFB($('screen'), socketURL(target),
        { credentials: password === null ? {} : { password }, shared: true });
    rfb = current; current.viewOnly = $('viewOnly').checked;
    current.scaleViewport = $('autoScale').checked; current.resizeSession = false;
    current.background = '#eaf0f8'; status('Đang kết nối…');
    current.addEventListener('credentialsrequired', () => {
        if (current !== rfb) return;
        requestCredentials({ title: $('deviceName').textContent,
            submit: value => { password = value; if (rfb === current && !manual) current.sendCredentials({ password: value }); },
            cancel: stop });
        message('Máy chủ đang dùng chế độ mật khẩu VNC.');
    });
    current.addEventListener('connect', () => {
        if (current !== rfb) return;
        retries = 0; $('empty').hidden = true; status('Đã kết nối', true);
        message($('viewOnly').checked ? 'Chế độ chỉ xem đang bật.' : 'Kéo chuột để vuốt. Bấm vào màn hình để gửi bàn phím.'); current.focus();
    });
    current.addEventListener('desktopname', event => { if (current === rfb) $('deviceName').textContent = event.detail.name || 'iPhone'; });
    current.addEventListener('securityfailure', () => {
        if (current !== rfb) return;
        stop(); message('Xác thực thất bại. Kiểm tra mật khẩu VNC trên iPhone.');
    });
    current.addEventListener('disconnect', () => {
        if (current !== rfb) return;
        rfb = null; $('empty').hidden = false;
        if (!manual && $('reconnect').checked && retries < 5) {
            const seconds = Math.min(2 ** (++retries), 16);
            retryTimer = setTimeout(connect, seconds * 1000); status(`Kết nối lại sau ${seconds}s…`);
            message(connectionMode() === 'usb' ? 'Đang chờ đường USB hoặc cổng chuyển tiếp phục hồi.' : 'Đang chờ iPhone hoặc mạng LAN phục hồi.');
        } else { stop(); message('Kết nối đã đóng. Nếu dùng HTTPS, kiểm tra chứng chỉ WSS trên cổng VNC.'); }
    });
}
$('connect').addEventListener('click', () => {
    if (!secure && connectionMode() === 'lan' && !window.confirm('HTTP/WS không mã hóa màn hình và thao tác. Chỉ tiếp tục trên LAN tin cậy.')) return;
    manual = false; retries = 0; connect();
});
$('loginForm').addEventListener('submit', event => { event.preventDefault(); finishLogin(false); });
$('cancel').addEventListener('click', () => finishLogin(true));
$('login').addEventListener('cancel', event => { event.preventDefault(); finishLogin(true); });
$('disconnect').addEventListener('click', stop); $('headerDisconnect').addEventListener('click', stop);
$('viewOnly').addEventListener('change', () => {
    if (rfb) rfb.viewOnly = $('viewOnly').checked;
    message($('viewOnly').checked ? 'Chế độ chỉ xem đang bật.' : 'Điều khiển phụ thuộc quyền trên iPhone.');
});
$('autoScale').addEventListener('change', () => { if (rfb) rfb.scaleViewport = $('autoScale').checked; });
function changeMode() {
    singleTarget = null;
    if (!manual || rfb || retryTimer) stop();
    updateConnectionUI();
    message(connectionMode() === 'usb' ? 'Hãy chạy chuyển tiếp USB cho cả cổng Web và VNC trên PC.' : 'Máy tính và iPhone cần ở cùng mạng LAN.');
}
$('modeLan').addEventListener('change', changeMode); $('modeUsb').addEventListener('change', changeMode);
$('usbPort').addEventListener('change', () => {
    const target = endpoint(); $('usbPort').value = String(target.port);
    try { sessionStorage.setItem('dk-usb-vnc-port', String(target.port)); } catch {}
    if (!manual || rfb || retryTimer) stop(); updateConnectionUI();
});
$('fullscreen').addEventListener('click', async () => {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await $('workspace').requestFullscreen(); }
    catch { message('Trình duyệt không cho phép toàn màn hình.'); }
});

let multiManager = null;
function initMultiDeviceViewer() {
    const STORAGE_KEY = 'dk-viewphone-devices-v1';
    const PREFS_KEY = 'dk-viewphone-multi-prefs-v1';
    const STATES = {idle:'Chưa kết nối',waiting:'Đang chờ',connecting:'Đang kết nối',online:'Online',retry:'Chờ kết nối lại',auth:'Cần mật khẩu',offline:'Offline',error:'Lỗi'};
    const privateIPv4 = host => {
        const parts = String(host).trim().split('.').map(Number);
        if (parts.length !== 4 || parts.some((n, i) => !Number.isInteger(n) || n < 0 || n > 255 || (i === 0 && n === 0))) return false;
        return parts[0] === 10 || parts[0] === 127 || (parts[0] === 192 && parts[1] === 168) || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31);
    };
    const makeId = () => globalThis.crypto?.randomUUID?.() || `device-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const cleanDevice = raw => ({
        device_id: String(raw.device_id || makeId()), name: String(raw.name || 'iPhone').slice(0, 60),
        host: String(raw.host || ''), vnc_port: Math.min(65535, Math.max(1, Number(raw.vnc_port) || 5901)),
        websocket_url: String(raw.websocket_url || ''), connection_mode: raw.connection_mode === 'usb' ? 'usb' : 'lan',
        connection_status: 'offline', view_only: raw.view_only !== false, auto_reconnect: raw.auto_reconnect !== false,
    });
    const currentDevice = cleanDevice({device_id:'current-iphone',name:'iPhone hiện tại',host:loopbackPage?'127.0.0.1':pageHost,
        vnc_port:devicePort,connection_mode:loopbackPage?'usb':'lan',view_only:true,auto_reconnect:true});
    let devices = [];
    try { const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]'); devices = Array.isArray(saved) ? saved.map(cleanDevice) : []; } catch {}
    if (!devices.length && (loopbackPage || privateIPv4(pageHost))) devices = [currentDevice];
    const saveDevices = () => {
        const safe = devices.map(({connection_status, ...device}) => device);
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(safe)); } catch { $('multiMessage').textContent = 'Trình duyệt không cho phép lưu danh sách thiết bị.'; }
    };
    let prefs = {columns:3,limit:6};
    try { prefs = {...prefs,...JSON.parse(localStorage.getItem(PREFS_KEY) || '{}')}; } catch {}
    prefs.columns = [2,3,4].includes(Number(prefs.columns)) ? Number(prefs.columns) : 3;
    prefs.limit = Math.min(12,Math.max(1,Number(prefs.limit)||6));
    $('gridColumns').value = String(prefs.columns); $('liveLimit').value = String(prefs.limit);

    function validateDevice(device, editingId = '') {
        if (!device.name.trim()) throw new Error('Tên thiết bị không được để trống.');
        if (device.connection_mode === 'lan' && !privateIPv4(device.host)) throw new Error('LAN chỉ chấp nhận IPv4 nội bộ hoặc loopback.');
        if (device.connection_mode === 'usb') device.host = '127.0.0.1';
        if (device.vnc_port < 1 || device.vnc_port > 65535) throw new Error('Cổng VNC phải nằm trong 1–65535.');
        if (device.connection_mode === 'usb' && devices.some(d => d.device_id !== editingId && d.connection_mode === 'usb' && d.vnc_port === device.vnc_port))
            throw new Error('Mỗi iPhone USB cần một cổng forward riêng trên PC.');
        if (device.websocket_url) {
            let url; try { url = new URL(device.websocket_url); } catch { throw new Error('WebSocket URL không hợp lệ.'); }
            if (!['ws:','wss:'].includes(url.protocol) || url.username || url.password) throw new Error('URL phải dùng ws/wss và không được chứa thông tin đăng nhập.');
            if (!privateIPv4(url.hostname) && !['localhost','[::1]','::1'].includes(url.hostname)) throw new Error('WebSocket chỉ được trỏ tới địa chỉ LAN hoặc loopback.');
            if (secure && url.protocol !== 'wss:') throw new Error('Trang HTTPS chỉ có thể kết nối bằng WSS.');
        }
        return device;
    }
    function deviceURL(device) {
        if (device.websocket_url) return device.websocket_url;
        const host = device.connection_mode === 'usb' ? '127.0.0.1' : device.host;
        return `${secure ? 'wss' : 'ws'}://${host}:${device.vnc_port}/websockify`;
    }
    function setMultiMessage(text) { $('multiMessage').textContent = text; }

    class DeviceSession {
        constructor(manager, device, card) {
            this.manager=manager; this.device=device; this.card=card; this.screen=card.querySelector('.card-screen');
            this.placeholder=card.querySelector('.card-placeholder'); this.rfb=null; this.password=null; this.retryTimer=null;
            this.connectTimer=null; this.retries=0; this.desired=false; this.state='idle';
        }
        setState(state, detail='') {
            this.state=state; this.device.connection_status=state;
            const statusEl=this.card.querySelector('.card-status'); statusEl.classList.toggle('online',state==='online');
            statusEl.querySelector('span:last-child').textContent=detail||STATES[state]||state;
            this.placeholder.hidden=state==='online'; this.manager.updateSummary(); applyFilter();
        }
        requestConnect() { this.desired=true; this.manager.request(this); }
        start() {
            if (!this.desired || this.rfb) return;
            let url; try { url=deviceURL(this.device); } catch (error) { this.setState('error',error.message); return; }
            this.clearTimers(); this.screen.replaceChildren(); this.setState('connecting');
            const current=new RFB(this.screen,url,{credentials:this.password===null?{}:{password:this.password},shared:true});
            this.rfb=current; current.viewOnly=this.device.view_only; current.scaleViewport=true; current.resizeSession=false; current.background='#eaf0f8';
            this.connectTimer=setTimeout(()=>{ if(current!==this.rfb)return; this.rfb=null; current.disconnect(); this.scheduleRetry('Hết thời gian kết nối'); },15000);
            current.addEventListener('credentialsrequired',()=>{
                if(current!==this.rfb)return; clearTimeout(this.connectTimer); this.setState('auth');
                requestCredentials({title:this.device.name,submit:value=>{this.password=value;if(this.rfb===current&&this.desired){this.setState('connecting');current.sendCredentials({password:value});}},cancel:()=>this.disconnect()});
            });
            current.addEventListener('connect',()=>{if(current!==this.rfb)return;clearTimeout(this.connectTimer);this.retries=0;this.setState('online');});
            current.addEventListener('securityfailure',()=>{if(current!==this.rfb)return;this.password=null;this.desired=false;this.rfb=null;current.disconnect();this.setState('error','Sai mật khẩu');this.manager.release(this);});
            current.addEventListener('disconnect',()=>{if(current!==this.rfb)return;this.rfb=null;clearTimeout(this.connectTimer);this.screen.replaceChildren();if(this.desired&&this.device.auto_reconnect)this.scheduleRetry();else{this.setState('offline');this.manager.release(this);}});
        }
        scheduleRetry(detail='') {
            clearTimeout(this.retryTimer); this.rfb=null; this.screen.replaceChildren(); this.manager.release(this);
            if(!this.desired||!this.device.auto_reconnect||this.retries>=5){this.desired=false;this.setState('offline',detail||'Đã ngắt');return;}
            const seconds=Math.min(2**(++this.retries),16);this.setState('retry',detail||`Thử lại sau ${seconds}s`);
            this.retryTimer=setTimeout(()=>{this.retryTimer=null;this.manager.request(this);},seconds*1000);
        }
        clearTimers(){clearTimeout(this.retryTimer);clearTimeout(this.connectTimer);this.retryTimer=this.connectTimer=null;}
        disconnect(){this.desired=false;this.retries=0;this.password=null;this.clearTimers();const old=this.rfb;this.rfb=null;if(old)old.disconnect();this.screen.replaceChildren();this.setState('offline');this.manager.release(this);}
        dispose(){this.disconnect();}
    }

    class MultiConnectionManager {
        constructor(){this.sessions=new Map();this.cards=new Map();this.visible=new Set();this.pending=new Set();this.observer=null;}
        activeCount(){return [...this.sessions.values()].filter(session=>!!session.rfb).length;}
        limit(){return Math.min(12,Math.max(1,Number($('liveLimit').value)||6));}
        isVisible(id){if(this.visible.has(id))return true;const card=this.cards.get(id);if(!card||card.hidden)return false;const rect=card.getBoundingClientRect();return rect.bottom>0&&rect.top<(window.innerHeight||document.documentElement.clientHeight);}
        request(session){
            if(!session.desired)return;
            if(!this.isVisible(session.device.device_id)){this.pending.add(session.device.device_id);session.setState('waiting','Chờ card hiển thị');return;}
            if(this.activeCount()>=this.limit()){this.pending.add(session.device.device_id);session.setState('waiting',`Chờ giới hạn ${this.limit()} Live View`);return;}
            this.pending.delete(session.device.device_id);session.start();
        }
        release(session){this.pending.delete(session.device.device_id);setTimeout(()=>this.pump(),0);this.updateSummary();}
        pump(){for(const id of [...this.pending]){const session=this.sessions.get(id);if(!session||!session.desired){this.pending.delete(id);continue;}if(this.activeCount()>=this.limit())break;if(this.isVisible(id)){this.pending.delete(id);session.start();}}}
        observe(card,id){this.cards.set(id,card);if(!this.observer){this.observer=new IntersectionObserver(entries=>{for(const entry of entries){const key=entry.target.dataset.id;if(entry.isIntersecting)this.visible.add(key);else this.visible.delete(key);}this.pump();},{rootMargin:'100px'});}this.observer.observe(card);}
        disconnectAll(){for(const session of this.sessions.values())session.disconnect();this.pending.clear();}
        disposeAll(){if(this.observer)this.observer.disconnect();for(const session of this.sessions.values())session.dispose();this.sessions.clear();this.cards.clear();this.visible.clear();this.pending.clear();}
        updateSummary(){const live=[...this.sessions.values()].filter(s=>s.state==='online').length;const desired=[...this.sessions.values()].filter(s=>s.desired).length;if(!$('multiPanel').hidden){$('state').textContent=`Multi View · ${live} live / ${this.limit()}`;$('status').classList.toggle('online',live>0);$('headerDisconnect').disabled=true;}setMultiMessage(`${live} phiên đang xem, ${desired} phiên được yêu cầu. Giới hạn hiện tại: ${this.limit()}.`);}
    }
    multiManager=new MultiConnectionManager();

    function cardFor(device) {
        const card=document.createElement('article');card.className='device-card';card.dataset.id=device.device_id;
        card.innerHTML='<div class="card-header"><input class="card-select" type="checkbox" aria-label="Chọn thiết bị"><div class="card-title"><strong></strong><span></span></div><div class="card-status"><i class="card-dot"></i><span>Chưa kết nối</span></div><button class="icon-button edit-device" title="Sửa">Sửa</button><button class="icon-button danger delete-device" title="Xóa">Xóa</button></div><button class="card-preview" title="Mở Single View"><div class="card-screen"></div><div class="card-placeholder"><div><div class="phone"></div><span>Chưa có Live View</span></div></div></button><div class="card-actions"><button class="connect-device">Kết nối</button><button class="disconnect-device" disabled>Ngắt</button><button class="open-device">Mở điều khiển</button></div>';
        card.querySelector('.card-title strong').textContent=device.name;card.querySelector('.card-title span').textContent=`${device.connection_mode.toUpperCase()} · ${device.connection_mode==='usb'?'127.0.0.1':device.host}:${device.vnc_port}`;
        const session=new DeviceSession(multiManager,device,card);multiManager.sessions.set(device.device_id,session);
        const connectButton=card.querySelector('.connect-device'),disconnectButton=card.querySelector('.disconnect-device');
        connectButton.addEventListener('click',()=>{session.requestConnect();connectButton.disabled=true;disconnectButton.disabled=false;});
        disconnectButton.addEventListener('click',()=>{session.disconnect();connectButton.disabled=false;disconnectButton.disabled=true;});
        const open=()=>openSingle(device);card.querySelector('.card-preview').addEventListener('click',open);card.querySelector('.open-device').addEventListener('click',open);
        card.querySelector('.edit-device').addEventListener('click',()=>openEditor(device.device_id));
        card.querySelector('.delete-device').addEventListener('click',()=>{session.dispose();devices=devices.filter(item=>item.device_id!==device.device_id);saveDevices();renderAll();});
        return card;
    }
    function renderAll(){multiManager.disposeAll();multiManager=new MultiConnectionManager();$('deviceGrid').replaceChildren();for(const device of devices){const card=cardFor(device);$('deviceGrid').append(card);multiManager.observe(card,device.device_id);}applyFilter();multiManager.updateSummary();}
    function applyFilter(){
        const query=$('deviceSearch').value.trim().toLowerCase(),filter=$('deviceFilter').value;let shown=0;
        for(const device of devices){const card=multiManager.cards.get(device.device_id);if(!card)continue;const session=multiManager.sessions.get(device.device_id);const online=session?.state==='online';const match=(!query||device.name.toLowerCase().includes(query)||device.host.includes(query))&&(filter==='all'||(filter==='online'&&online)||(filter==='offline'&&!online));card.classList.toggle('hidden-card',!match);if(match)shown++;}
        $('noDevices').hidden=shown!==0;
    }
    function selectedSessions(){return [...$('deviceGrid').querySelectorAll('.device-card')].filter(card=>card.querySelector('.card-select').checked&&!card.classList.contains('hidden-card')).map(card=>multiManager.sessions.get(card.dataset.id)).filter(Boolean);}
    function openEditor(id=''){
        const device=devices.find(item=>item.device_id===id);$('deviceEditorTitle').textContent=device?'Sửa thiết bị':'Thêm thiết bị';$('deviceId').value=device?.device_id||'';$('deviceLabel').value=device?.name||`iPhone ${devices.length+1}`;$('deviceMode').value=device?.connection_mode||'lan';$('deviceHost').value=device?.host||(privateIPv4(pageHost)?pageHost:'');$('deviceVncPort').value=String(device?.vnc_port||5901);$('deviceWebsocket').value=device?.websocket_url||'';$('deviceViewOnly').checked=device?.view_only!==false;$('deviceReconnect').checked=device?.auto_reconnect!==false;$('deviceFormError').textContent='';$('deviceEditor').showModal();
    }
    function openSingle(device){
        multiManager.disconnectAll();singleTarget={host:device.connection_mode==='usb'?'127.0.0.1':device.host,port:device.vnc_port,mode:device.connection_mode,websocketUrl:device.websocket_url||''};$('modeUsb').checked=device.connection_mode==='usb';$('modeLan').checked=device.connection_mode!=='usb';$('usbPort').value=String(device.vnc_port);$('deviceName').textContent=device.name;$('viewOnly').checked=false;switchView('single');updateConnectionUI();status('Sẵn sàng kết nối');message('Nhấn Kết nối để điều khiển riêng thiết bị này. Các Live View đã được giải phóng.');
    }
    function switchView(view){
        const multi=view==='multi';$('singlePanel').hidden=multi;$('multiPanel').hidden=!multi;$('singleTab').classList.toggle('active',!multi);$('multiTab').classList.toggle('active',multi);$('singleTab').setAttribute('aria-pressed',String(!multi));$('multiTab').setAttribute('aria-pressed',String(multi));
        if(multi){stop();$('deviceName').textContent='Multi-Device LAN Viewer';multiManager.updateSummary();setTimeout(()=>multiManager.pump(),0);}else{multiManager.disconnectAll();updateConnectionUI();}
    }
    $('singleTab').addEventListener('click',()=>switchView('single'));$('multiTab').addEventListener('click',()=>switchView('multi'));
    $('addDevice').addEventListener('click',()=>openEditor());$('cancelDevice').addEventListener('click',()=>$('deviceEditor').close());
    $('deviceForm').addEventListener('submit',event=>{event.preventDefault();try{const id=$('deviceId').value;const device=validateDevice(cleanDevice({device_id:id||makeId(),name:$('deviceLabel').value.trim(),connection_mode:$('deviceMode').value,host:$('deviceHost').value.trim(),vnc_port:Number($('deviceVncPort').value),websocket_url:$('deviceWebsocket').value.trim(),view_only:$('deviceViewOnly').checked,auto_reconnect:$('deviceReconnect').checked}),id);const index=devices.findIndex(item=>item.device_id===id);if(index>=0)devices[index]=device;else devices.push(device);saveDevices();$('deviceEditor').close();renderAll();}catch(error){$('deviceFormError').textContent=error.message;}});
    $('connectSelected').addEventListener('click',()=>{const sessions=selectedSessions();if(!sessions.length){setMultiMessage('Hãy chọn ít nhất một thiết bị.');return;}for(const session of sessions)session.requestConnect();});
    $('disconnectSelected').addEventListener('click',()=>{const sessions=selectedSessions();if(!sessions.length){setMultiMessage('Hãy chọn ít nhất một thiết bị.');return;}for(const session of sessions)session.disconnect();});
    $('deviceSearch').addEventListener('input',applyFilter);$('deviceFilter').addEventListener('change',applyFilter);
    $('gridColumns').addEventListener('change',()=>{const value=[2,3,4].includes(Number($('gridColumns').value))?Number($('gridColumns').value):3;$('deviceGrid').className=`device-grid columns-${value}`;prefs.columns=value;try{localStorage.setItem(PREFS_KEY,JSON.stringify(prefs));}catch{}});
    $('liveLimit').addEventListener('change',()=>{prefs.limit=Math.min(12,Math.max(1,Number($('liveLimit').value)||6));$('liveLimit').value=String(prefs.limit);try{localStorage.setItem(PREFS_KEY,JSON.stringify(prefs));}catch{}multiManager.pump();multiManager.updateSummary();});
    $('deviceMode').addEventListener('change',()=>{if($('deviceMode').value==='usb')$('deviceHost').value='127.0.0.1';});
    $('deviceGrid').className=`device-grid columns-${prefs.columns}`;renderAll();saveDevices();
}

const hasMultiUI = typeof document.querySelector === 'function' && document.querySelector('#multiPanel');
if (hasMultiUI) initMultiDeviceViewer();
window.addEventListener('pagehide', () => { stop(); if (multiManager) multiManager.disposeAll(); loginQueue.length=0; pendingLogin=null; });
updateConnectionUI(); status('Chưa kết nối');
