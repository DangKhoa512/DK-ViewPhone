// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
// Independent HTTP/WebSocket transport. No RFB, no FarmBIOS wire protocol.
#include "StreamServer.h"
#include "WebSocket.h"
#include "../Common/Clock.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <algorithm>
#include <arpa/inet.h>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <map>
#include <mutex>
#include <poll.h>
#include <sstream>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

namespace dkss {
static std::string lower(std::string value) {
    for(char &c:value) if(c>='A'&&c<='Z') c=char(c-'A'+'a');
    return value;
}
static std::string trim(std::string value) {
    auto first=value.find_first_not_of(" \t\r\n"),last=value.find_last_not_of(" \t\r\n");
    return first==std::string::npos?std::string{}:value.substr(first,last-first+1);
}
static Packet textPacket(const std::string &value) {
    return websocketPacket(1,std::span(reinterpret_cast<const uint8_t *>(value.data()),value.size()));
}
static bool nonblocking(int fd) {
    int flags=fcntl(fd,F_GETFL,0);
    return flags>=0 && fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 && fcntl(fd,F_SETFD,FD_CLOEXEC)==0;
}
struct StreamServer::Impl {
    struct Connection {
        int fd=-1;
        std::string ip,http;
        WebSocketParser parser;
        OutputQueue output;
        bool upgraded=false,authenticated=false,closing=false;
        double created=nowSeconds(),received=created,written=created,authenticatedAt=0,lastPing=created;
    };
    Config config;
    std::string webRoot;
    Metrics &metrics;
    std::function<void(size_t)> changed;
    int listener=-1,wakeRead=-1,wakeWrite=-1;
    std::thread thread;
    std::atomic<bool> running{false};
    std::atomic<size_t> viewerCount{0};
    std::mutex pendingMutex;
    Packet pendingVideo,pendingMetrics,cachedVideo;
    std::map<int,Connection> connections;
    std::map<std::string,std::pair<unsigned,double>> failedAuth;

    Impl(Config c,std::string root,Metrics &m,std::function<void(size_t)> callback)
        : config(std::move(c)),webRoot(std::move(root)),metrics(m),changed(std::move(callback)) {}
    void wake() { if(wakeWrite>=0) { const char byte=1; (void)write(wakeWrite,&byte,1); } }
    void setViewers(size_t count) {
        size_t previous=viewerCount.exchange(count);
        if(previous!=count && changed) changed(count);
        if(!count) cachedVideo.reset();
    }
    void remove(int fd) {
        auto item=connections.find(fd);
        if(item==connections.end()) return;
        bool authenticated=item->second.authenticated;
        close(fd); connections.erase(item);
        if(authenticated) setViewers(viewerCount.load()-1);
    }
    void closeWebSocket(Connection &connection,uint16_t code) {
        if(connection.closing) return;
        connection.output.discardPendingVideo();
        std::array<uint8_t,2> reason{static_cast<uint8_t>(code>>8),static_cast<uint8_t>(code)};
        if(!connection.output.control(websocketPacket(8,reason))) { connection.created=0; }
        connection.closing=true;
    }
    bool control(Connection &connection,const std::string &json) {
        if(connection.output.control(textPacket(json))) return true;
        connection.created=0; return false;
    }
    void http(Connection &connection) {
        auto end=connection.http.find("\r\n\r\n");
        if(end==std::string::npos) return;
        std::istringstream input(connection.http.substr(0,end+2));
        std::string line,method,path,version;
        std::getline(input,line); std::istringstream request(line); request>>method>>path>>version;
        std::map<std::string,std::string> headers;
        bool valid=method=="GET" && version=="HTTP/1.1" && connection.http.find('\0')==std::string::npos;
        while(std::getline(input,line)) {
            auto colon=line.find(':');
            if(colon==std::string::npos) { valid=false; break; }
            auto key=lower(trim(line.substr(0,colon))),value=trim(line.substr(colon+1));
            if(key.empty() || headers.count(key)) { valid=false; break; }
            headers[key]=value;
        }
        auto respond=[&](int status,const std::string &type,std::span<const uint8_t> body) {
            std::string title=status==200?"OK":status==404?"Not Found":"Bad Request";
            std::string header="HTTP/1.1 "+std::to_string(status)+" "+title+"\r\nContent-Type: "+type+
                "\r\nContent-Length: "+std::to_string(body.size())+
                "\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"+
                "Content-Security-Policy: default-src 'self'; connect-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n";
            auto packet=std::make_shared<Bytes>(header.begin(),header.end());
            packet->insert(packet->end(),body.begin(),body.end()); connection.output.control(packet); connection.closing=true;
        };
        if(!valid || !headers.count("host")) { respond(400,"text/plain",{}); return; }
        if(path=="/stream") {
            NSString *key=[NSString stringWithUTF8String:headers["sec-websocket-key"].c_str()];
            NSData *decoded=key?[[NSData alloc] initWithBase64EncodedString:key options:0]:nil;
            bool upgrade=lower(headers["upgrade"])=="websocket" && headers["sec-websocket-version"]=="13";
            bool connectionUpgrade=false;
            std::istringstream parts(lower(headers["connection"]));
            while(std::getline(parts,line,',')) if(trim(line)=="upgrade") connectionUpgrade=true;
            // Browsers must originate from the viewer they loaded. Non-browser
            // clients may omit Origin, but still require the secret token.
            auto origin=headers.find("origin");
            bool sameOrigin=origin==headers.end() || origin->second=="http://"+headers["host"];
            if(!upgrade || !connectionUpgrade || decoded.length!=16 || !sameOrigin ||
                ![[decoded base64EncodedStringWithOptions:0] isEqualToString:key]) { respond(400,"text/plain",{}); return; }
            auto denied=failedAuth.find(connection.ip);
            if(denied!=failedAuth.end() && denied->second.first>=5 && nowSeconds()-denied->second.second<60) {
                respond(400,"text/plain",{}); return;
            }
            std::string challenge=headers["sec-websocket-key"]+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
            uint8_t digest[CC_SHA1_DIGEST_LENGTH]; CC_SHA1(challenge.data(),static_cast<CC_LONG>(challenge.size()),digest);
            NSString *accept=[[NSData dataWithBytes:digest length:sizeof(digest)] base64EncodedStringWithOptions:0];
            std::string response="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+
                std::string(accept.UTF8String)+"\r\n\r\n";
            connection.output.control(std::make_shared<Bytes>(response.begin(),response.end()));
            connection.upgraded=true;
            std::string remainder=connection.http.substr(end+4); connection.http.clear();
            if(!remainder.empty()) consume(connection,std::span(reinterpret_cast<const uint8_t *>(remainder.data()),remainder.size()));
            return;
        }
        const char *name=path=="/"||path=="/index.html"?"index.html":path=="/viewer.js"?"viewer.js":path=="/style.css"?"style.css":nullptr;
        if(!name) { respond(404,"text/plain",{}); return; }
        NSString *filename=[NSString stringWithUTF8String:(webRoot+"/"+name).c_str()];
        NSData *asset=[NSData dataWithContentsOfFile:filename];
        if(!asset || asset.length>1024*1024) { respond(404,"text/plain",{}); return; }
        respond(200,path=="/viewer.js"?"text/javascript; charset=utf-8":path=="/style.css"?"text/css; charset=utf-8":"text/html; charset=utf-8",
            std::span<const uint8_t>(static_cast<const uint8_t *>(asset.bytes),static_cast<size_t>(asset.length)));
    }
    void consume(Connection &connection,std::span<const uint8_t> bytes) {
        if(!connection.parser.append(bytes)) { closeWebSocket(connection,connection.parser.error()); return; }
        while(auto message=connection.parser.next()) {
            connection.received=nowSeconds();
            if(message->opcode==8) { closeWebSocket(connection,1000); break; }
            if(message->opcode==9) {
                if(!connection.output.control(websocketPacket(10,message->data))) connection.created=0;
                continue;
            }
            if(message->opcode==10) continue;
            if(message->opcode!=1) { closeWebSocket(connection,1003); break; }
            NSData *data=[NSData dataWithBytes:message->data.data() length:message->data.size()];
            id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if(![value isKindOfClass:NSDictionary.class] || ![value[@"type"] isKindOfClass:NSString.class]) {
                closeWebSocket(connection,1007); break;
            }
            NSDictionary *command=value; NSString *type=command[@"type"];
            if(!connection.authenticated) {
                NSString *secret=command[@"token"];
                bool accepted=[type isEqualToString:@"auth"] && [secret isKindOfClass:NSString.class] && secret.length==64 &&
                    constantTimeToken(config.token,std::string(secret.UTF8String ?: ""));
                if(!accepted) {
                    if(failedAuth.size()>=64 && !failedAuth.count(connection.ip)) failedAuth.erase(failedAuth.begin());
                    auto &failure=failedAuth[connection.ip];
                    if(nowSeconds()-failure.second>60) failure.first=0;
                    ++failure.first; failure.second=nowSeconds(); closeWebSocket(connection,1008); break;
                }
                if(viewerCount.load()>=config.maxClients) { closeWebSocket(connection,1013); break; }
                connection.authenticated=true; connection.authenticatedAt=nowSeconds(); failedAuth.erase(connection.ip);
                control(connection,"{\"type\":\"ready\",\"protocol\":1,\"viewOnly\":true,\"input\":false}");
                if(cachedVideo) connection.output.latest(cachedVideo);
                setViewers(viewerCount.load()+1);
            } else if([type isEqualToString:@"ping"] && [command[@"t"] isKindOfClass:NSNumber.class]) {
                double stamp=[command[@"t"] doubleValue];
                if(std::isfinite(stamp) && stamp>=0 && stamp<=1e15)
                    control(connection,"{\"type\":\"pong\",\"t\":"+std::to_string(stamp)+"}");
            } else {
                // This release has no input handler, even after authentication.
                closeWebSocket(connection,1008); break;
            }
        }
        if(connection.parser.error()) closeWebSocket(connection,connection.parser.error());
    }
    void distribute() {
        Packet video,stats;
        { std::lock_guard guard(pendingMutex); video=std::move(pendingVideo); stats=std::move(pendingMetrics); }
        if(video && viewerCount.load()) cachedVideo=video;
        for(auto &[fd,connection]:connections) {
            (void)fd;
            if(!connection.authenticated || connection.closing) continue;
            if(video) {
                uint64_t before=connection.output.replaced; connection.output.latest(video);
                metrics.dropped.fetch_add(connection.output.replaced-before);
            }
            if(stats && !connection.output.control(stats)) connection.created=0;
        }
    }
    void loop() {
        while(running.load()) @autoreleasepool {
            distribute();
            std::vector<pollfd> polling{{listener,POLLIN,0},{wakeRead,POLLIN,0}};
            for(auto &[fd,c]:connections) polling.push_back({fd,static_cast<short>(POLLIN|(c.output.pending()?POLLOUT:0)),0});
            int rc=poll(polling.data(),static_cast<nfds_t>(polling.size()),100);
            if(rc<0 && errno!=EINTR) break;
            if(polling[1].revents&POLLIN) { char buffer[256]; while(read(wakeRead,buffer,sizeof(buffer))>0) {} }
            if(polling[0].revents&POLLIN) for(int attempts=0;attempts<8;++attempts) {
                sockaddr_in peer{}; socklen_t size=sizeof(peer);
                int fd=accept(listener,reinterpret_cast<sockaddr *>(&peer),&size);
                if(fd<0) break;
                int yes=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
                if(connections.size()>=32 || !nonblocking(fd)) { close(fd); continue; }
                char ip[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&peer.sin_addr,ip,sizeof(ip));
                Connection c; c.fd=fd; c.ip=ip; connections.emplace(fd,std::move(c));
            }
            std::vector<int> removing;
            for(size_t index=2;index<polling.size();++index) {
                int fd=polling[index].fd; auto item=connections.find(fd); if(item==connections.end()) continue;
                auto &c=item->second; short events=polling[index].revents;
                bool bad=events&(POLLERR|POLLHUP|POLLNVAL);
                if(!bad && (events&POLLIN) && !c.closing) {
                    uint8_t buffer[4096]; ssize_t count=recv(fd,buffer,sizeof(buffer),0);
                    if(count==0 || (count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR)) bad=true;
                    else if(count>0) {
                        c.received=nowSeconds();
                        if(c.upgraded) consume(c,std::span(buffer,static_cast<size_t>(count)));
                        else {
                            c.http.append(reinterpret_cast<const char *>(buffer),static_cast<size_t>(count));
                            if(c.http.size()>8192) bad=true; else http(c);
                        }
                    }
                }
                if(!bad && (events&POLLOUT)) {
                    size_t budget=65536;
                    while(budget && c.output.pending()) {
                        auto bytes=c.output.bytes(); size_t size=std::min(bytes.size(),budget);
                        ssize_t sent=send(fd,bytes.data(),size,0);
                        if(sent<0) { if(errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR) bad=true; break; }
                        if(!sent) break;
                        c.output.consumed(static_cast<size_t>(sent)); budget-=static_cast<size_t>(sent);
                        metrics.socketBytes.fetch_add(static_cast<uint64_t>(sent)); c.written=nowSeconds();
                    }
                }
                double now=nowSeconds();
                if(c.authenticated && !c.closing && now-c.lastPing>=15) {
                    c.lastPing=now;
                    if(!c.output.control(websocketPacket(9,{}))) bad=true;
                }
                if(!c.created || (!c.authenticated && now-c.created>5) || now-c.received>45 ||
                   (c.authenticated && now-c.authenticatedAt>3600) ||
                   (c.output.pending() && now-c.written>5) || (c.closing && !c.output.pending())) bad=true;
                if(bad) removing.push_back(fd);
            }
            for(int fd:removing) remove(fd);
        }
        for(auto &[fd,c]:connections) { (void)c; close(fd); }
        connections.clear(); setViewers(0);
        running=false;
    }
};
StreamServer::StreamServer(Config c,std::string root,Metrics &m,std::function<void(size_t)> changed)
    :impl(std::make_unique<Impl>(std::move(c),std::move(root),m,std::move(changed))) {}
StreamServer::~StreamServer() { stop(); }
bool StreamServer::start(std::string &error) {
    if(impl->running.load()) return true;
    if(!validToken(impl->config.token)) { error="authentication token not configured"; return false; }
    sockaddr_in address{}; address.sin_family=AF_INET; address.sin_port=htons(impl->config.port);
    if(inet_pton(AF_INET,impl->config.address.c_str(),&address.sin_addr)!=1) { error="invalid IPv4 bind"; return false; }
    uint32_t ip=ntohl(address.sin_addr.s_addr);
    if(!((ip>>24)==127 || (ip>>24)==10 || (ip&0xfff00000)==0xac100000 || (ip&0xffff0000)==0xc0a80000)) {
        error="private or loopback IPv4 required"; return false;
    }
    impl->listener=socket(AF_INET,SOCK_STREAM,0);
    int yes=1; setsockopt(impl->listener,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    int pipeFDs[2]={-1,-1};
    if(impl->listener<0 || !nonblocking(impl->listener) ||
       bind(impl->listener,reinterpret_cast<sockaddr *>(&address),sizeof(address)) || listen(impl->listener,16) || pipe(pipeFDs)) {
        error=std::strerror(errno); if(impl->listener>=0) close(impl->listener); impl->listener=-1; return false;
    }
    impl->wakeRead=pipeFDs[0]; impl->wakeWrite=pipeFDs[1]; nonblocking(impl->wakeRead); nonblocking(impl->wakeWrite);
    impl->running=true; impl->thread=std::thread([this] { impl->loop(); }); return true;
}
void StreamServer::publish(const FrameInfo &info,const std::vector<uint8_t> &jpeg) {
    if(!impl->running.load() || !impl->viewerCount.load() || jpeg.size()!=info.jpegBytes) return;
    auto header=encodeHeader(info); Bytes frame(header.begin(),header.end()); frame.insert(frame.end(),jpeg.begin(),jpeg.end());
    auto packet=websocketPacket(2,frame);
    { std::lock_guard guard(impl->pendingMutex); if(impl->pendingVideo) ++impl->metrics.dropped; impl->pendingVideo=std::move(packet); }
    impl->wake();
}
void StreamServer::publishMetrics(const std::string &json) {
    if(!impl->running.load() || json.size()>2048) return;
    { std::lock_guard guard(impl->pendingMutex); impl->pendingMetrics=textPacket(json); }
    impl->wake();
}
size_t StreamServer::viewers() const { return impl->viewerCount.load(); }
bool StreamServer::healthy() const { return impl->running.load(); }
uint16_t StreamServer::localPort() const {
    sockaddr_in address{}; socklen_t length=sizeof(address);
    return impl->listener>=0 && !getsockname(impl->listener,reinterpret_cast<sockaddr *>(&address),&length)?ntohs(address.sin_port):0;
}
void StreamServer::stop() {
    if(!impl) return;
    if(impl->running.exchange(false)) impl->wake();
    if(impl->thread.joinable()) impl->thread.join();
    for(int fd:{impl->listener,impl->wakeRead,impl->wakeWrite}) if(fd>=0) close(fd);
    impl->listener=impl->wakeRead=impl->wakeWrite=-1;
    std::lock_guard guard(impl->pendingMutex); impl->pendingVideo.reset(); impl->pendingMetrics.reset();
}
} // namespace dkss
