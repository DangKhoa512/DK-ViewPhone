'use strict';

const path = require('node:path');
const fs = require('node:fs');
const {app, BrowserWindow, ipcMain, protocol, session} = require('electron');
const {scanLAN} = require('./scanner.cjs');

protocol.registerSchemesAsPrivileged([{
    scheme: 'dkview',
    privileges: {standard: true, secure: true, supportFetchAPI: true},
}]);

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();

let mainWindow = null;
const smokeResultPath = process.env.DK_DESKTOP_SMOKE_RESULT || '';
const previewPath = process.env.DK_DESKTOP_PREVIEW_PATH || '';

function viewerRoot() {
    return app.isPackaged
        ? path.join(process.resourcesPath, 'webclients')
        : path.join(__dirname, '..', 'layout', 'usr', 'share', 'trollvnc', 'webclients');
}

async function serveViewer(request) {
    const url = new URL(request.url);
    const requested = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const relative = requested === 'index.html' ? 'index.vnc' : requested;
    const root = path.resolve(viewerRoot());
    const file = path.resolve(root, relative);
    if (file !== root && !file.startsWith(root + path.sep))
        return new Response('Not found', {status: 404});
    const mime = {
        '.vnc': 'text/html; charset=utf-8',
        '.html': 'text/html; charset=utf-8',
        '.js': 'application/javascript; charset=utf-8',
        '.css': 'text/css; charset=utf-8',
        '.png': 'image/png',
        '.svg': 'image/svg+xml',
    }[path.extname(file).toLowerCase()] || 'application/octet-stream';
    try {
        return new Response(await fs.promises.readFile(file), {
            status: 200,
            headers: {'Content-Type': mime, 'Cache-Control': 'no-store'},
        });
    } catch {
        return new Response('Not found', {status: 404});
    }
}

function createWindow() {
    mainWindow = new BrowserWindow({
        title: 'ĐK ViewPhone Desktop',
        width: 1600,
        height: 960,
        minWidth: 1000,
        minHeight: 680,
        backgroundColor: '#eef3f9',
        show: !smokeResultPath && !previewPath,
        icon: app.isPackaged
            ? path.join(process.resourcesPath, 'icon.png')
            : path.join(__dirname, 'build', 'icon.png'),
        webPreferences: {
            preload: path.join(__dirname, 'preload.cjs'),
            nodeIntegration: false,
            contextIsolation: true,
            sandbox: true,
            webSecurity: true,
            devTools: !app.isPackaged,
        },
    });
    mainWindow.removeMenu();
    mainWindow.webContents.setWindowOpenHandler(() => ({action: 'deny'}));
    mainWindow.webContents.on('will-navigate', (event, url) => {
        if (!url.startsWith('dkview://app/')) event.preventDefault();
    });
    mainWindow.loadURL('dkview://app/index.html');
    if (smokeResultPath) {
        mainWindow.webContents.once('did-finish-load', async () => {
            try {
                const result = await mainWindow.webContents.executeJavaScript(`
                    (async () => {
                        const scan = await window.dkDesktop.scanLAN();
                        return {
                            title: document.title,
                            desktop_api: typeof window.dkDesktop?.scanLAN === 'function',
                            scan_button_visible: !document.getElementById('scanLan').hidden,
                            legacy_tabs: document.querySelectorAll('#singleTab,#multiTab').length,
                            device_grid: !!document.getElementById('deviceGrid'),
                            focus_panel: !!document.getElementById('focusPanel'),
                            scanned_subnets: scan.subnets,
                            discovered_devices: scan.devices.length
                        };
                    })()
                `);
                fs.writeFileSync(smokeResultPath, JSON.stringify({status: 'passed', ...result}, null, 2));
                app.exit(0);
            } catch (error) {
                fs.writeFileSync(smokeResultPath, JSON.stringify({status: 'failed', error: String(error)}, null, 2));
                app.exit(1);
            }
        });
    } else if (previewPath) {
        mainWindow.webContents.once('did-finish-load', async () => {
            try {
                await mainWindow.webContents.executeJavaScript(`
                    document.getElementById('loadDemo').click();
                    document.querySelector('.open-device')?.click();
                `);
                await new Promise(resolve => setTimeout(resolve, 2500));
                const image = await mainWindow.webContents.capturePage();
                fs.writeFileSync(previewPath, image.toPNG());
                app.exit(0);
            } catch (error) {
                console.error(error);
                app.exit(1);
            }
        });
    }
    mainWindow.on('closed', () => { mainWindow = null; });
}

ipcMain.handle('dk:scan-lan', async event => {
    const frameURL = event.senderFrame?.url || '';
    if (!frameURL.startsWith('dkview://app/')) throw new Error('Nguồn gọi quét LAN không hợp lệ.');
    return scanLAN({ports: [5801, 5901], timeoutMs: 320, concurrency: 72});
});

app.whenReady().then(() => {
    protocol.handle('dkview', serveViewer);
    session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
    createWindow();
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
