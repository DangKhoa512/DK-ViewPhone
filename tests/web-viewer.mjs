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
const document = Object.assign(new EventTarget(), {
    body: {dataset: {rfbPort: '5901'}},
    getElementById() { return null; },
});
class Observer {
    static instances = [];
    constructor(callback) {
        this.callback = callback;
        this.disconnected = false;
        Observer.instances.push(this);
    }
    observe(target) { this.target = target; }
    disconnect() { this.disconnected = true; }
}
const source = readFileSync(new URL('../layout/usr/share/trollvnc/webclients/viewer.js', import.meta.url), 'utf8')
    .replace(/^import RFB from [^\n]+\n/m, '');
const sandbox = {
    RFB, window, document,
    MutationObserver: Observer, ResizeObserver: Observer,
    getComputedStyle: element => element.padding || {},
    location: {hostname: '192.168.50.2', port: '5801', protocol: 'http:'},
    setTimeout: (fn, ms) => { timers.set(++timerId, {fn, ms}); return timerId; },
    clearTimeout: id => timers.delete(id),
};
runInNewContext(source, sandbox);

const {ManagedRfbSession, privateIPv4, retryDelay, socketURL, normalizeFrameScale} = window.__DK_VIEWPHONE_TEST__;
for (const [input, expected] of [
    [undefined, 100], [null, 100], ['', 100], [true, 100], ['invalid', 100],
    [NaN, 100], [Infinity, 100], [-20, 50], [0, 50], [50, 50], ['75', 75],
    [99, 100], [103, 105], [150, 150], [999, 150],
]) {
    assert.equal(normalizeFrameScale(input), expected, `Frame scale: ${String(input)}`);
}
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

// Promotion during an authentication challenge keeps the same request and RFB.
session = makeSession({role: 'preview'});
session.requestStart();
latest().emit('credentialsrequired');
const authenticatingRfb = latest();
const authRequest = credentialRequest;
const authenticatingCount = connections.length;
session.setPresentation('focus', {viewOnly: false});
assert.equal(session.state, 'auth');
assert.equal(session.rfb, authenticatingRfb);
assert.equal(credentialRequest, authRequest);
assert.equal(connections.length, authenticatingCount);
authRequest.submit('same-challenge');
assert.equal(authenticatingRfb.credentials.password, 'same-challenge');
authenticatingRfb.emit('connect');
assert.equal(state, 'online');
session.disconnect();

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

// A live transport changes presentation without recreating its RFB or credentials.
session = makeSession({role: 'preview'});
session.requestStart();
assert.equal(latest().qualityLevel, 3);
assert.equal(latest().compressionLevel, 6);
latest().emit('connect');
const sharedRfb = latest();
const countBeforePresentation = connections.length;
session.password = 'temporary-presentation-test';
session.setPresentation('focus', {viewOnly: false, scaleViewport: false});
assert.equal(session.rfb, sharedRfb);
assert.equal(connections.length, countBeforePresentation);
assert.equal(sharedRfb.qualityLevel, 8);
assert.equal(sharedRfb.compressionLevel, 2);
assert.equal(sharedRfb.viewOnly, false);
assert.equal(sharedRfb.scaleViewport, false);
assert.equal(session.password, 'temporary-presentation-test');
session.setPresentation('preview', {viewOnly: false, scaleViewport: false});
assert.equal(session.rfb, sharedRfb);
assert.equal(connections.length, countBeforePresentation);
assert.equal(sharedRfb.qualityLevel, 3);
assert.equal(sharedRfb.compressionLevel, 6);
assert.equal(sharedRfb.viewOnly, true);
assert.equal(sharedRfb.scaleViewport, true);
session.setViewOnly(false);
assert.equal(latest().viewOnly, false);
session.setScale(false);
assert.equal(latest().scaleViewport, false);
session.disconnect();
session.setPresentation('focus', {viewOnly: false});
assert.equal(session.desired, false);
assert.equal(session.rfb, null);
assert.equal(connections.length, countBeforePresentation);

// Authentication failure clears the in-memory password and never retries.
session = makeSession();
session.password = 'temporary';
session.requestStart();
latest().emit('securityfailure');
assert.equal(session.password, null);
assert.equal(state, 'error');
assert.equal(timers.size, 0);

// Fit the phone into the CSS stage, including stage-only layout changes and
// rotation/fullscreen, without feeding dimensions back into the parent layout.
function aspectElement(classes = []) {
    const values = new Set(classes);
    return {
        style: {
            setProperty(name, value) { this[name] = value; },
            removeProperty(name) { delete this[name]; },
        },
        classList: {
            contains: name => values.has(name),
            add: name => values.add(name),
            remove: name => values.delete(name),
        },
        querySelector() { return this.canvas || null; },
        replaceChildren() { this.canvas = null; },
    };
}
const screen = aspectElement();
screen.canvas = {width: 600, height: 1000};
const stage = aspectElement(['focus-workspace']);
stage.clientWidth = 600;
stage.clientHeight = 800;
sandbox.trackScreenAspect(screen, stage);
const [canvasObserver, stageObserver] = Observer.instances.slice(-2);
assert.equal(screen.style.width, '480px');
assert.equal(screen.style.height, '800px');
assert.equal(stage.style.width, undefined);
assert.equal(stage.style.height, undefined);
assert.equal(stage.style['--focus-screen-width'], undefined);
stage.clientWidth = 500;
stage.clientHeight = 600;
stageObserver.callback();
assert.equal(screen.style.width, '360px');
assert.equal(screen.style.height, '600px');
screen.canvas = {width: 1000, height: 600};
canvasObserver.callback();
assert.equal(screen.style.width, '500px');
assert.equal(screen.style.height, '300px');
stage.clientWidth = 1920;
stage.clientHeight = 1080;
document.dispatchEvent(new Event('fullscreenchange'));
assert.equal(screen.style.width, '1800px');
assert.equal(screen.style.height, '1080px');
stage.padding = {paddingLeft: '10px', paddingRight: '10px', paddingTop: '10px', paddingBottom: '10px'};
stage.clientWidth = 520;
stage.clientHeight = 620;
stageObserver.callback();
assert.equal(screen.style.width, '500px');
assert.equal(screen.style.height, '300px');

// Replacing tracking and disposing the session release all observers/listeners.
sandbox.trackScreenAspect(screen, stage);
assert.equal(canvasObserver.disconnected, true);
assert.equal(stageObserver.disconnected, true);
const activeObservers = Observer.instances.slice(-2);
makeSession({target: screen}).dispose();
assert.ok(activeObservers.every(observer => observer.disconnected));
assert.equal(screen.__dkAspectCleanup, undefined);
assert.equal(screen.style.width, undefined);
assert.equal(screen.style.height, undefined);
stage.clientWidth = 900;
window.dispatchEvent(new Event('resize'));
document.dispatchEvent(new Event('fullscreenchange'));
assert.equal(screen.style.width, undefined);
assert.equal(stage.classList.contains('screen-ready'), false);

// Preview cards retain their own aspect ratio without focus sizing/listeners.
const preview = aspectElement();
preview.canvas = {width: 1000, height: 600};
const card = aspectElement(['card-preview']);
const previousObservers = Observer.instances.length;
sandbox.trackScreenAspect(preview, card);
assert.equal(Observer.instances.length, previousObservers + 1);
assert.equal(card.style['--screen-ratio'], '1000 / 600');
assert.equal(preview.style.width, undefined);
// A downscaled mirror keeps the original framebuffer ratio, avoiding feedback
// between rounded thumbnail pixels and the card's CSS dimensions.
preview.canvas = {width: 169, height: 302, dataset: {framebufferWidth: '180', framebufferHeight: '320'}};
Observer.instances.at(-1).callback();
assert.equal(card.style['--screen-ratio'], '180 / 320');
preview.__dkAspectCleanup();

console.log('Dashboard session, aspect fitting and observer lifecycle checks passed');
