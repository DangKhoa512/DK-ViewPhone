// Behavioral wrapper tests with noVNC's public event contract. No browser secrets.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';

class Element extends EventTarget {
    checked = false; disabled = false; value = ''; textContent = ''; hidden = false;
    classList = { toggle() {} };
    focus() {} showModal() {} close() {}
    click() { this.dispatchEvent(new Event('click')); }
}
const elements = new Map();
const el = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
el('reconnect').checked = el('autoScale').checked = true;
const timers = new Map(); let timerId = 0;
const connections = [];
class RFB extends EventTarget {
    constructor(target, url, options) { super(); this.url = url; this.options = options; connections.push(this); }
    focus() {}
    disconnect() { this.emit('disconnect', { clean: true }); }
    emit(name, detail = {}) { const event = new Event(name); event.detail = detail; this.dispatchEvent(event); }
}
const window = new EventTarget(); window.confirm = () => true;
const source = readFileSync(new URL('../layout/usr/share/trollvnc/webclients/viewer.js', import.meta.url), 'utf8')
    .replace(/^import RFB from [^\n]+\n/m, '');
runInNewContext(source, { RFB, window, document: { getElementById: el, body: { dataset: { rfbPort: '5901' } } },
    location: { hostname: '192.168.50.2', port: '5801', protocol: 'http:' },
    setTimeout: (fn, ms) => { timers.set(++timerId, { fn, ms }); return timerId; },
    clearTimeout: id => timers.delete(id) });
const latest = () => connections.at(-1);
function login() {
    el('connect').click(); el('password').value = 'synthetic-test-only';
    el('loginForm').dispatchEvent(new Event('submit', { cancelable: true }));
    assert.equal(el('password').value, '');
    assert.equal(latest().url, 'ws://192.168.50.2:5901/websockify');
    assert.ok(!latest().url.includes('synthetic'));
}
function retry() {
    assert.equal(timers.size, 1);
    const [id, task] = timers.entries().next().value; timers.delete(id); task.fn(); return task.ms;
}
login(); latest().emit('connect');
// Actual regression: noVNC uses clean=true for a server-side close of an
// established session. That must still reconnect unless the user opted out.
const before = connections.length;
latest().emit('disconnect', { clean: true }); assert.equal(retry(), 2000);
assert.equal(connections.length, before + 1);
latest().emit('connect'); el('disconnect').click();
assert.equal(timers.size, 0); assert.equal(el('connect').disabled, false);

login(); latest().emit('securityfailure');
assert.equal(timers.size, 0); assert.equal(el('connect').disabled, false);
login(); latest().emit('disconnect', { clean: false });
el('disconnect').click(); assert.equal(timers.size, 0);
login(); el('reconnect').checked = false; latest().emit('disconnect', { clean: true });
assert.equal(timers.size, 0); el('reconnect').checked = true;

login(); const delays = [];
for (let i = 0; i < 5; ++i) { latest().emit('disconnect', { clean: false }); delays.push(retry()); }
latest().emit('disconnect', { clean: false });
assert.deepEqual(delays, [2000, 4000, 8000, 16000, 16000]);
assert.equal(timers.size, 0); assert.equal(el('connect').disabled, false);
console.log('Viewer reconnect intent, retry budget, manual-off and authentication failure checks passed');
