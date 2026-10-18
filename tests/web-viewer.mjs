// Behavioral tests for the shared noVNC session used by previews and focus control.
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import assert from 'node:assert/strict';

const timers = new Map();
let timerId = 0;
const connections = [];

class RFB extends EventTarget {
    constructor(target, url, options) {
        super();
        this.target = target;
        this.url = url;
        this.options = options;
        this.qualityLevel = 6;
        this.compressionLevel = 2;
        connections.push(this);
    }
    focus() {}
    disconnect() { this.emit('disconnect', {clean: true}); }
    sendCredentials(value) { this.credentials = value; }
    emit(name, detail = {}) {
        const event = new Event(name);
        event.detail = detail;
        this.dispatchEvent(event);
    }
}

const window = new EventTarget();
const document = {
    body: {dataset: {rfbPort: '5901'}},
    getElementById() { return null; },
};
const source = readFileSync(new URL('../layout/usr/share/trollvnc/webclients/viewer.js', import.meta.url), 'utf8')
    .replace(/^import RFB from [^\n]+\n/m, '');
runInNewContext(source, {
    RFB, window, document,
    location: {hostname: '192.168.50.2', port: '5801', protocol: 'http:'},
    setTimeout: (fn, ms) => { timers.set(++timerId, {fn, ms}); return timerId; },
    clearTimeout: id => timers.delete(id),
});

const {ManagedRfbSession, privateIPv4, retryDelay, socketURL} = window.__DK_VIEWPHONE_TEST__;
const target = {children: [], replaceChildren() { this.children = []; }};
let state = '';
let credentialRequest = null;
const makeSession = (overrides = {}) => new ManagedRfbSession({
    role: 'focus',
    target,
    url: () => 'ws://192.168.50.2:5901/websockify',
    onState: next => { state = next; },
    onCredentials: request => { credentialRequest = request; },
    ...overrides,
});
const latest = () => connections.at(-1);
const runOnlyTimer = expectedDelay => {
    assert.equal(timers.size, 1);
    const [id, task] = timers.entries().next().value;
    timers.delete(id);
    assert.equal(task.ms, expectedDelay);
    task.fn();
};

assert.equal(privateIPv4('192.168.1.158'), true);
assert.equal(privateIPv4('8.8.8.8'), false);
assert.deepEqual([1, 2, 3, 4, 5].map(retryDelay), [2000, 4000, 8000, 16000, 16000]);
assert.equal(socketURL({host: '192.168.1.10', vnc_port: 5901, connection_mode: 'lan'}),
    'ws://192.168.1.10:5901/websockify');
assert.equal(socketURL({host: '192.168.1.10', vnc_port: 5907, connection_mode: 'usb'}),
    'ws://127.0.0.1:5907/websockify');

// Security type None starts without an invented password.
let session = makeSession();
session.requestStart();
assert.equal(state, 'connecting');
assert.deepEqual(Object.keys(latest().options.credentials), []);
assert.equal(latest().viewOnly, true);
assert.equal(latest().qualityLevel, 8);
latest().emit('connect');
assert.equal(state, 'online');
assert.equal(timers.size, 0);

// A focus session accepts a real challenge, keeps the credential in memory only,
// and never places it in the WebSocket URL.
latest().emit('credentialsrequired');
assert.equal(state, 'auth');
credentialRequest.submit('synthetic-test-only');
assert.equal(latest().credentials.password, 'synthetic-test-only');
assert.ok(!latest().url.includes('synthetic'));
latest().emit('connect');
session.disconnect();
assert.equal(state, 'offline');
assert.equal(timers.size, 0);

// Cancelling authentication is a manual disconnect, not a reconnect loop.
credentialRequest = null;
session = makeSession();
session.requestStart();
latest().emit('credentialsrequired');
credentialRequest.cancel();
assert.equal(state, 'offline');
assert.equal(timers.size, 0);

// Both clean and unclean server disconnects consume the bounded exponential budget.
session = makeSession();
session.requestStart();
latest().emit('connect');
const expected = [2000, 4000, 8000, 16000, 16000];
for (const delay of expected) {
    latest().emit('disconnect', {clean: delay === 2000});
    runOnlyTimer(delay);
}
latest().emit('disconnect', {clean: false});
assert.equal(state, 'offline');
assert.equal(timers.size, 0);

// Preview and focus tune separate noVNC instances; view-only can change live.
session = makeSession({role: 'preview'});
session.requestStart();
assert.equal(latest().qualityLevel, 3);
assert.equal(latest().compressionLevel, 6);
session.setViewOnly(false);
assert.equal(latest().viewOnly, false);
session.setScale(false);
assert.equal(latest().scaleViewport, false);
session.disconnect();

// Authentication failure clears the in-memory password and never retries.
session = makeSession();
session.password = 'temporary';
session.requestStart();
latest().emit('securityfailure');
assert.equal(session.password, null);
assert.equal(state, 'error');
assert.equal(timers.size, 0);

console.log('Dashboard session authentication, reconnect, LAN/USB and focus/preview checks passed');
