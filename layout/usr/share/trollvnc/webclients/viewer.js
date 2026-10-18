// GPL-2.0-only. Offline wrapper around the bundled, unmodified noVNC client.
import RFB from './novnc/core/rfb.js';
const $ = id => document.getElementById(id);
let rfb = null, password = null, retryTimer = null, retries = 0, manual = true;
const pageHost = location.hostname;
const devicePort = Number(document.body.dataset.rfbPort) || 5901;
const secure = location.protocol === 'https:';
const loopbackPage = pageHost === '127.0.0.1' || pageHost === 'localhost' || pageHost === '::1';
$('modeLan').checked = !loopbackPage; $('modeUsb').checked = loopbackPage;
try { const saved = Number(sessionStorage.getItem('dk-usb-vnc-port')); if (saved >= 1 && saved <= 65535) $('usbPort').value = String(saved); } catch {}
function connectionMode() { return $('modeUsb').checked ? 'usb' : 'lan'; }
function endpoint() {
    if (connectionMode() === 'usb') {
        const selected = Number($('usbPort').value);
        return { host: '127.0.0.1', port: selected >= 1 && selected <= 65535 ? selected : 5901 };
    }
    return { host: pageHost, port: devicePort };
}
function updateConnectionUI() {
    const mode = connectionMode(), target = endpoint();
    $('usbPortField').hidden = mode !== 'usb';
    $('address').textContent = mode === 'usb'
        ? `USB · 127.0.0.1:${target.port} → iPhone:5901`
        : `LAN · ${target.host}:${target.port} · Web ${location.port || (secure ? 443 : 80)}`;
    if (mode === 'usb') {
        $('transport').textContent = secure
            ? 'USB + WSS · Cần forward cổng HTTP và VNC; chứng chỉ phải hợp lệ cho 127.0.0.1. Mỗi iPhone dùng cặp cổng PC riêng.'
            : 'USB + WS · Forward cổng HTTP và VNC bằng iproxy/usbmuxd. Mỗi iPhone dùng cặp cổng PC riêng.';
    } else {
        $('transport').textContent = secure
            ? 'LAN qua HTTPS + WSS · Chứng chỉ phải được trình duyệt tin cậy cho cả hai cổng.'
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
function stop() {
    manual = true; password = null; retries = 0;
    clearTimeout(retryTimer); retryTimer = null;
    const previous = rfb; rfb = null; if (previous) previous.disconnect();
    $('password').value = ''; if ($('login').open) $('login').close();
    $('empty').hidden = false; status('Đã ngắt kết nối');
}
function connect() {
    clearTimeout(retryTimer); retryTimer = null;
    if (manual) return;
    const target = endpoint();
    const current = new RFB($('screen'), `${secure ? 'wss' : 'ws'}://${target.host}:${target.port}/websockify`,
        { credentials: password === null ? {} : { password }, shared: true });
    rfb = current; current.viewOnly = $('viewOnly').checked;
    current.scaleViewport = $('autoScale').checked; current.resizeSession = false;
    current.background = '#eaf0f8'; status('Đang kết nối…');
    current.addEventListener('credentialsrequired', () => {
        if (current !== rfb) return;
        $('login').showModal(); $('password').focus();
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
        // This noVNC version labels established server-side closes as clean,
        // including a killed worker. Only our explicit Disconnect/auth failure
        // cancels the user's reconnect intent.
        if (!manual && $('reconnect').checked && retries < 5) {
            const seconds = Math.min(2 ** (++retries), 16);
            retryTimer = setTimeout(connect, seconds * 1000); status(`Kết nối lại sau ${seconds}s…`);
            message(connectionMode() === 'usb' ? 'Đang chờ đường USB hoặc cổng chuyển tiếp phục hồi.' : 'Đang chờ iPhone hoặc mạng LAN phục hồi. Nếu IP đổi, mở URL mới trong Cài đặt.');
        } else { stop(); message('Kết nối đã đóng. Nếu dùng HTTPS, kiểm tra chứng chỉ WSS trên cổng VNC.'); }
    });
}
$('connect').addEventListener('click', () => {
    if (!secure && connectionMode() === 'lan' && !window.confirm('HTTP/WS không mã hóa màn hình và thao tác. Chỉ tiếp tục trên LAN tin cậy.')) return;
    manual = false; retries = 0; connect();
});
$('loginForm').addEventListener('submit', event => {
    event.preventDefault(); password = $('password').value; $('password').value = '';
    $('login').close(); if (rfb && !manual) rfb.sendCredentials({ password });
});
$('cancel').addEventListener('click', () => { $('login').close(); stop(); });
$('login').addEventListener('cancel', stop);
$('disconnect').addEventListener('click', stop); $('headerDisconnect').addEventListener('click', stop);
$('viewOnly').addEventListener('change', () => {
    if (rfb) rfb.viewOnly = $('viewOnly').checked;
    message($('viewOnly').checked ? 'Chế độ chỉ xem đang bật.' : 'Điều khiển phụ thuộc quyền của mật khẩu và Settings trên iPhone.');
});
$('autoScale').addEventListener('change', () => { if (rfb) rfb.scaleViewport = $('autoScale').checked; });
function changeMode() {
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
window.addEventListener('pagehide', stop); updateConnectionUI(); status('Chưa kết nối');
