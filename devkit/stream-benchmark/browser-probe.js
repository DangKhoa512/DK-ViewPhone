// GPL-2.0-only. Same probe for JPEG and noVNC; payload bytes exclude WS/TCP headers.
(() => {
    window.dkProbe={paints:0,bytes:0,messages:0,opened:0,closed:0,metrics:null,errors:[]};
    const WS=window.WebSocket;
    window.WebSocket=new Proxy(WS,{
        construct(Target,args) {
            const socket=Reflect.construct(Target,args);
            socket.addEventListener('open',()=>dkProbe.opened++);
            socket.addEventListener('close',()=>dkProbe.closed++);
            socket.addEventListener('message',event=>{
                dkProbe.messages++;
                dkProbe.bytes+=typeof event.data==='string'?new TextEncoder().encode(event.data).length:
                    event.data.byteLength??event.data.size??0;
                if(typeof event.data==='string')try{const m=JSON.parse(event.data);if(m.type==='metrics')dkProbe.metrics=m;}catch{}
            });return socket;
        }
    });
    const draw=CanvasRenderingContext2D.prototype.drawImage;
    CanvasRenderingContext2D.prototype.drawImage=function(...args){
        const result=draw.apply(this,args);
        // Count only presentation to the connected canvas, not offscreen blits.
        if(this.canvas.isConnected&&this.canvas.width>100&&this.canvas.height>100)dkProbe.paints++;
        return result;
    };
    window.addEventListener('error',event=>dkProbe.errors.push(String(event.message).slice(0,160)));
})();
