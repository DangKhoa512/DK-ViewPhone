'use strict';

const net = require('node:net');
const os = require('node:os');
const {performance} = require('node:perf_hooks');

function isPrivateIPv4(address) {
    if (net.isIP(address) !== 4) return false;
    const [a, b] = address.split('.').map(Number);
    return a === 10 || a === 127 || (a === 192 && b === 168) ||
        (a === 172 && b >= 16 && b <= 31);
}

function subnetsFromInterfaces(interfaces = os.networkInterfaces()) {
    const subnets = new Set();
    for (const entries of Object.values(interfaces)) {
        for (const info of entries || []) {
            const family = typeof info.family === 'string' ? info.family : String(info.family);
            if (family !== 'IPv4' && family !== '4') continue;
            if (info.internal || !isPrivateIPv4(info.address) || info.address.startsWith('127.')) continue;
            const parts = info.address.split('.');
            subnets.add(`${parts[0]}.${parts[1]}.${parts[2]}.0/24`);
        }
    }
    return [...subnets].slice(0, 4);
}

function hostsForSubnet(cidr) {
    const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.0\/24$/.exec(String(cidr));
    if (!match) throw new Error('Desktop scanner only accepts a private /24 subnet.');
    const octets = match.slice(1).map(Number);
    if (octets.some(value => value > 255) || !isPrivateIPv4(`${octets.join('.')}.1`))
        throw new Error('Desktop scanner only accepts a private /24 subnet.');
    return Array.from({length: 254}, (_, index) => `${octets.join('.')}.${index + 1}`);
}

function probePort(host, port, timeoutMs = 320) {
    return new Promise(resolve => {
        let settled = false;
        const socket = net.createConnection({host, port});
        const finish = open => {
            if (settled) return;
            settled = true;
            socket.destroy();
            resolve(open);
        };
        socket.setTimeout(timeoutMs);
        socket.once('connect', () => finish(true));
        socket.once('timeout', () => finish(false));
        socket.once('error', () => finish(false));
    });
}

async function mapLimit(items, limit, worker) {
    const output = new Array(items.length);
    let cursor = 0;
    async function next() {
        while (cursor < items.length) {
            const index = cursor++;
            output[index] = await worker(items[index], index);
        }
    }
    await Promise.all(Array.from({length: Math.min(limit, items.length)}, next));
    return output;
}

async function scanHosts(hosts, options = {}) {
    const ports = options.ports || [5801, 5901];
    const timeoutMs = options.timeoutMs || 320;
    const concurrency = Math.min(96, Math.max(1, options.concurrency || 64));
    const results = await mapLimit(hosts, concurrency, async host => {
        if (!isPrivateIPv4(host)) return null;
        const states = await Promise.all(ports.map(port => probePort(host, port, timeoutMs)));
        const openPorts = ports.filter((_, index) => states[index]);
        return openPorts.length ? {host, ports: openPorts} : null;
    });
    return results.filter(Boolean);
}

async function scanLAN(options = {}) {
    const started = performance.now();
    const subnets = options.subnets || subnetsFromInterfaces();
    if (!subnets.length) throw new Error('Không tìm thấy card mạng IPv4 LAN riêng.');
    const ownAddresses = new Set();
    for (const entries of Object.values(os.networkInterfaces())) {
        for (const info of entries || []) if (net.isIP(info.address) === 4) ownAddresses.add(info.address);
    }
    const hosts = [...new Set(subnets.flatMap(hostsForSubnet))].filter(host => !ownAddresses.has(host));
    const open = await scanHosts(hosts, options);
    const devices = open.filter(item => item.ports.includes(5901)).map(item => {
        const suffix = item.host.split('.').at(-1);
        return {
            host: item.host,
            ports: item.ports,
            vnc_port: 5901,
            http_port: item.ports.includes(5801) ? 5801 : null,
            web_url: item.ports.includes(5801) ? `http://${item.host}:5801/` : null,
            name: item.ports.includes(5801) ? `ĐK ViewPhone · ${suffix}` : `VNC · ${suffix}`,
        };
    });
    return {
        subnets,
        devices,
        web_only: open.filter(item => item.ports.includes(5801) && !item.ports.includes(5901)),
        duration_ms: Math.round(performance.now() - started),
    };
}

module.exports = {
    isPrivateIPv4,
    subnetsFromInterfaces,
    hostsForSubnet,
    probePort,
    scanHosts,
    scanLAN,
};
