// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
export function parseFrame(buffer) {
    if(!(buffer instanceof ArrayBuffer) || buffer.byteLength<40 || buffer.byteLength>40+4*1024*1024) throw new Error('Kích thước frame không hợp lệ');
    const data=new DataView(buffer);
    if(data.getUint32(0)!==0x444b5353 || data.getUint8(4)!==1 || data.getUint8(5)!==1 ||
        data.getUint16(6)!==40 || data.getUint16(34)!==0) throw new Error('Protocol frame không hợp lệ');
    const width=data.getUint32(24),height=data.getUint32(28),rotation=data.getUint16(32),bytes=data.getUint32(36);
    if(!width || !height || width>4096 || height>4096 || !bytes || bytes!==buffer.byteLength-40 ||
        ![0,90,180,270].includes(rotation)) throw new Error('Nội dung frame không hợp lệ');
    return {sequence:data.getBigUint64(8),sourceMicros:data.getBigUint64(16),width,height,rotation,
        jpeg:new Uint8Array(buffer,40)};
}

export class LatestDecoder {
    constructor(decode,draw,onDrop,onError) {
        this.decode=decode;this.draw=draw;this.onDrop=onDrop;this.onError=onError;
        this.pending=null;this.busy=false;this.generation=0;this.closed=false;
    }
    push(frame) {
        if(this.closed) return;
        if(this.pending) this.onDrop();
        this.pending=frame;void this.pump();
    }
    async pump() {
        if(this.busy || this.closed) return;
        this.busy=true;
        try {
            while(this.pending && !this.closed) {
                const frame=this.pending,generation=this.generation;this.pending=null;
                let bitmap;
                try {
                    const started=performance.now();bitmap=await this.decode(frame);
                    if(!this.closed && generation===this.generation) this.draw(bitmap,frame,performance.now()-started);
                } catch(error) {
                    if(!this.closed && generation===this.generation) {this.onDrop();this.onError(error);}
                } finally {bitmap?.close?.();}
            }
        } finally {this.busy=false;}
    }
    close() {this.closed=true;this.pending=null;this.generation++;}
}

function startViewer() {
    const $=id=>document.getElementById(id),screen=$('screen'),context=screen.getContext('2d',{alpha:false});
    let socket=null,decoder=null,token='',wanted=false,retries=0,retryTimer=null,pingTimer=null,generation=0,lastSequence=null;
    let drawn=0,dropped=0,receivedBytes=0,lastDrawn=0,lastBytes=0,lastTick=performance.now();
    function status(text,state='') {$('status').textContent=text;$('status').dataset.state=state;}
    function dispose() {
        generation++;clearTimeout(retryTimer);clearInterval(pingTimer);retryTimer=pingTimer=null;
        decoder?.close();decoder=null;
        const previous=socket;socket=null;
        if(previous) {previous.onclose=null;previous.onmessage=null;previous.onerror=null;previous.close();}
        $('disconnect').disabled=true;$('connect').disabled=false;
    }
    function disconnect() {
        wanted=false;token='';$('token').value='';dispose();status('Đã ngắt');
    }
    function connect() {
        if(!wanted || document.hidden) return;
        dispose();const turn=generation;lastSequence=null;
        status(retries?'Đang kết nối lại…':'Đang kết nối…');$('connect').disabled=true;$('disconnect').disabled=false;
        const current=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/stream`);
        socket=current;current.binaryType='arraybuffer';
        decoder=new LatestDecoder(frame=>createImageBitmap(new Blob([frame.jpeg],{type:'image/jpeg'})),
            (bitmap,frame,ms)=>{
                if(turn!==generation || document.hidden) return;
                if(bitmap.width!==frame.width || bitmap.height!==frame.height) throw new Error('Kích thước JPEG không khớp');
                if(screen.width!==frame.width || screen.height!==frame.height) {screen.width=frame.width;screen.height=frame.height;}
                context.drawImage(bitmap,0,0);screen.style.display='block';$('empty').hidden=true;
                drawn++;$('decode').textContent=`${ms.toFixed(1)} ms`;$('geometry').textContent=`${frame.width} × ${frame.height}`;
            },()=>{dropped++;},()=>status('Không đọc được khung ảnh','error'));
        current.onopen=()=>{if(turn===generation) current.send(JSON.stringify({type:'auth',token}));};
        current.onmessage=event=>{
            if(turn!==generation) return;
            try {
                if(typeof event.data==='string') {
                    const message=JSON.parse(event.data);
                    if(message.type==='ready' && message.protocol===1 && message.viewOnly===true) {
                        retries=0;status('Đang xem','online');
                        clearInterval(pingTimer);pingTimer=setInterval(()=>{
                            if(current.readyState===WebSocket.OPEN) current.send(JSON.stringify({type:'ping',t:performance.now()}));
                        },10000);
                    } else if(message.type==='pong' && Number.isFinite(message.t)) {
                        const rtt=performance.now()-message.t;
                        if(rtt>=0 && rtt<60000) $('rtt').textContent=`${rtt.toFixed(0)} ms`;
                    }
                    return;
                }
                const frame=parseFrame(event.data);
                receivedBytes+=event.data.byteLength;
                if(lastSequence!==null) {
                    if(frame.sequence<=lastSequence) {dropped++;return;}
                    const missing=frame.sequence-lastSequence-1n;
                    dropped+=Number(missing>1000000n?1000000n:missing);
                }
                lastSequence=frame.sequence;decoder?.push(frame);
            } catch {status('Dữ liệu không hợp lệ','error');wanted=false;dispose();token='';}
        };
        current.onerror=()=>{if(turn===generation) status('Không kết nối được','error');};
        current.onclose=event=>{
            if(turn!==generation) return;
            decoder?.close();decoder=null;socket=null;clearInterval(pingTimer);pingTimer=null;
            $('connect').disabled=false;$('disconnect').disabled=true;
            if(event.code===1008 || event.code===1007) {wanted=false;token='';status('Mã kết nối không hợp lệ hoặc phiên đã hết hạn','error');return;}
            if(event.code===1013) {wanted=false;token='';status('Đã đủ số viewer cho phép','error');return;}
            if(wanted && !document.hidden && retries<5) {
                const delay=Math.min(16000,1000*2**retries++);status('Mất kết nối, đang thử lại…');retryTimer=setTimeout(connect,delay);
            } else status(document.hidden?'Đã tạm dừng':'Đã ngắt');
        };
    }
    $('connection').addEventListener('submit',event=>{
        event.preventDefault();const value=$('token').value.trim();
        if(!/^[0-9a-f]{64}$/.test(value)) {status('Nhập đủ mã kết nối từ iPhone','error');return;}
        token=value;$('token').value='';wanted=true;retries=0;connect();
    });
    $('disconnect').addEventListener('click',disconnect);
    $('autoScale').addEventListener('change',()=>$('stage').classList.toggle('fit',$('autoScale').checked));
    $('fullscreen').addEventListener('click',()=>{
        const action=document.fullscreenElement?document.exitFullscreen():$('screenArea').requestFullscreen();
        action?.catch(()=>status('Không mở được toàn màn hình','error'));
    });
    document.addEventListener('visibilitychange',()=>{
        if(document.hidden) {dispose();if(wanted) status('Đã tạm dừng');}
        else if(wanted) {retries=0;connect();}
    });
    window.addEventListener('pagehide',disconnect);
    setInterval(()=>{
        const now=performance.now(),seconds=(now-lastTick)/1000;
        $('fps').textContent=socket?.readyState===WebSocket.OPEN?((drawn-lastDrawn)/seconds).toFixed(1):'—';
        $('throughput').textContent=socket?.readyState===WebSocket.OPEN?`${((receivedBytes-lastBytes)/1024/seconds).toFixed(1)} kB/s`:'—';
        $('dropped').textContent=String(dropped);lastDrawn=drawn;lastBytes=receivedBytes;lastTick=now;
    },1000);
}
if(typeof document!=='undefined') startViewer();
