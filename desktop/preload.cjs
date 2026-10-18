'use strict';

const {contextBridge, ipcRenderer} = require('electron');

contextBridge.exposeInMainWorld('dkDesktop', Object.freeze({
    scanLAN: () => ipcRenderer.invoke('dk:scan-lan'),
    platform: process.platform,
}));
