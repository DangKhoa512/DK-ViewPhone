'use strict';

const assert = require('node:assert/strict');
const net = require('node:net');
const test = require('node:test');
const {
    isPrivateIPv4,
    subnetsFromInterfaces,
    hostsForSubnet,
    probePort,
    scanHosts,
} = require('../scanner.cjs');

test('detects private IPv4 and derives bounded /24 networks', () => {
    assert.equal(isPrivateIPv4('192.168.1.158'), true);
    assert.equal(isPrivateIPv4('172.16.2.3'), true);
    assert.equal(isPrivateIPv4('8.8.8.8'), false);
    const subnets = subnetsFromInterfaces({
        WiFi: [{family: 'IPv4', internal: false, address: '192.168.1.157'}],
        Public: [{family: 'IPv4', internal: false, address: '8.8.8.8'}],
        Loopback: [{family: 'IPv4', internal: true, address: '127.0.0.1'}],
    });
    assert.deepEqual(subnets, ['192.168.1.0/24']);
    const hosts = hostsForSubnet(subnets[0]);
    assert.equal(hosts.length, 254);
    assert.equal(hosts[0], '192.168.1.1');
    assert.equal(hosts.at(-1), '192.168.1.254');
    assert.throws(() => hostsForSubnet('8.8.8.0/24'));
});

test('probes open ports and returns only private hosts with an open endpoint', async t => {
    const server = net.createServer(socket => socket.end());
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => server.close());
    const port = server.address().port;
    assert.equal(await probePort('127.0.0.1', port, 200), true);
    const result = await scanHosts(['127.0.0.1', '8.8.8.8'], {
        ports: [port], timeoutMs: 200, concurrency: 2,
    });
    assert.deepEqual(result, [{host: '127.0.0.1', ports: [port]}]);
});
