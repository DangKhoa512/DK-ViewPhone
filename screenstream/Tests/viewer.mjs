// GPL-2.0-only. Decoder queue and disposal are exercised without a fake server.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../Web/viewer.js',import.meta.url),'utf8');
const {parseFrame,LatestDecoder}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
function frame() {
    const buffer=new ArrayBuffer(44),data=new DataView(buffer);
    data.setUint32(0,0x444b5353);data.setUint8(4,1);data.setUint8(5,1);data.setUint16(6,40);
    data.setBigUint64(8,0x0102030405060708n);data.setBigUint64(16,123456789n);
    data.setUint32(24,750);data.setUint32(28,1334);data.setUint16(32,90);data.setUint32(36,4);
    new Uint8Array(buffer,40).set([0xff,0xd8,0xff,0xd9]);return buffer;
}
const decoded=parseFrame(frame());assert.equal(decoded.sequence,0x0102030405060708n);assert.equal(decoded.rotation,90);
assert.deepEqual([...decoded.jpeg],[0xff,0xd8,0xff,0xd9]);
for(const at of [0,4,5,7,34,39]) {const bad=frame();new Uint8Array(bad)[at]^=255;assert.throws(()=>parseFrame(bad));}
for(let length=0;length<40;length++) assert.throws(()=>parseFrame(new ArrayBuffer(length)));
assert.throws(()=>parseFrame(frame().slice(0,43)));
let finish,drawn=[],dropped=0,closed=0;
const decoder=new LatestDecoder(value=>new Promise(resolve=>{finish=()=>resolve({id:value,close(){closed++;}});}),
    bitmap=>drawn.push(bitmap.id),()=>dropped++,error=>{throw error;});
decoder.push(1);decoder.push(2);decoder.push(3);assert.equal(dropped,1);
finish();await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(drawn,[1]);
finish();await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(drawn,[1,3]);assert.equal(closed,2);
decoder.push(4);decoder.close();finish();await new Promise(resolve=>setImmediate(resolve));
assert.deepEqual(drawn,[1,3]);assert.equal(closed,3);
assert(!/localStorage|sessionStorage|novnc/i.test(source));
console.log('PASS: DKSS frame vectors, malformed bounds, latest decoder, bitmap disposal and no credential storage');
