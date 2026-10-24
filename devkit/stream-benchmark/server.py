"""Loopback-only synthetic iPhone fixture and bounded telemetry, Python 3.

Not shipped in either DEB. Stop the process to release its temporary display
assertion; no Auto-Lock preference or system service is changed.
"""
import argparse,ctypes,json,signal,time
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path

parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True)
args=parser.parse_args();fixture=Path(args.directory)/'fixture.html'
latest={};assertion=None;iokit=None;cf=None
try:
    cf=ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    cf.CFStringCreateWithCString.restype=ctypes.c_void_p
    cf.CFStringCreateWithCString.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_uint32]
    cf.CFRelease.argtypes=[ctypes.c_void_p]
    iokit=ctypes.CDLL('/System/Library/Frameworks/IOKit.framework/IOKit')
    create=iokit.IOPMAssertionCreateWithName
    create.argtypes=[ctypes.c_void_p,ctypes.c_uint32,ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)]
    create.restype=ctypes.c_int
    kind=cf.CFStringCreateWithCString(None,b'PreventUserIdleDisplaySleep',0x08000100)
    reason=cf.CFStringCreateWithCString(None,b'DK temporary streaming benchmark',0x08000100)
    identifier=ctypes.c_uint32();code=create(kind,255,reason,ctypes.byref(identifier))
    cf.CFRelease(kind);cf.CFRelease(reason)
    if not code:assertion=identifier.value
    assertion_status={'supported':True,'code':code,'held':assertion is not None}
except (AttributeError,OSError):assertion_status={'supported':False,'held':False}

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,status,body,kind='application/json'):
        self.send_response(status);self.send_header('Content-Type',kind)
        self.send_header('Content-Length',str(len(body)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(body)
    def do_GET(self):
        if self.path.split('?',1)[0]=='/fixture.html':self.reply(200,fixture.read_bytes(),'text/html; charset=utf-8')
        elif self.path=='/status':self.reply(200,json.dumps({'displayAssertion':assertion_status,'sample':latest,'ageSeconds':time.monotonic()-latest.get('receivedMonotonic',time.monotonic())}).encode())
        else:self.reply(404,b'{}')
    def do_POST(self):
        size=int(self.headers.get('Content-Length','0'))
        if self.path!='/sample' or not 0<size<=1024:self.reply(400,b'{}');return
        try:
            value=json.loads(self.rfile.read(size))
            if not isinstance(value,dict) or value.get('phase') not in (0,1,2):raise ValueError()
            safe={key:value[key] for key in ('phase','frames','paused','width','height')}
            if not all(isinstance(v,(int,bool)) for v in safe.values()):raise ValueError()
            latest.clear();latest.update(safe,receivedMonotonic=time.monotonic())
            self.reply(200,b'{}')
        except (ValueError,KeyError,TypeError):self.reply(400,b'{}')

server=HTTPServer(('127.0.0.1',5803),Handler);server.timeout=.5
stopping=False
def stop(*_):
    global stopping
    stopping=True
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
print(json.dumps({'fixtureServerReady':True,'displayAssertion':assertion_status}),flush=True)
try:
    while not stopping:server.handle_request()
finally:
    server.server_close()
    if assertion is not None:iokit.IOPMAssertionRelease(ctypes.c_uint32(assertion))
