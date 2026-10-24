// GPL-2.0-only. Real loopback HTTP/WS auth and connection isolation on macOS.
#include "../Streaming/StreamServer.h"
#include <arpa/inet.h>
#include <cassert>
#include <chrono>
#include <fstream>
#include <iostream>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

static void sendAll(int fd,const std::vector<uint8_t> &bytes) {
    size_t at=0;
    while(at<bytes.size()) { auto count=send(fd,bytes.data()+at,bytes.size()-at,0); assert(count>0); at+=static_cast<size_t>(count); }
}
static std::vector<uint8_t> readBytes(int fd,size_t count) {
    std::vector<uint8_t> out(count); size_t at=0;
    while(at<count) { auto result=recv(fd,out.data()+at,count-at,0); assert(result>0); at+=static_cast<size_t>(result); }
    return out;
}
static void command(int fd,const std::string &json) {
    assert(json.size()<126);
    std::vector<uint8_t> frame{0x81,static_cast<uint8_t>(0x80|json.size()),1,2,3,4};
    for(size_t i=0;i<json.size();++i) frame.push_back(json[i]^frame[2+i%4]); sendAll(fd,frame);
}
static std::pair<uint8_t,std::vector<uint8_t>> readFrame(int fd) {
    auto head=readBytes(fd,2); assert(!(head[1]&0x80)); uint64_t length=head[1]&127;
    if(length==126) {auto bytes=readBytes(fd,2);length=bytes[0]*256+bytes[1];}
    else if(length==127) {length=0;for(auto byte:readBytes(fd,8)) length=length*256+byte;}
    assert(length<1024*1024); return {head[0]&15,readBytes(fd,static_cast<size_t>(length))};
}
static int openWS(uint16_t port) {
    int fd=socket(AF_INET,SOCK_STREAM,0); assert(fd>=0);
    timeval timeout{3,0}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    sockaddr_in target{};target.sin_family=AF_INET;target.sin_port=htons(port);inet_pton(AF_INET,"127.0.0.1",&target.sin_addr);
    assert(connect(fd,reinterpret_cast<sockaddr *>(&target),sizeof(target))==0);
    std::string request="GET /stream HTTP/1.1\r\nHost: 127.0.0.1:"+std::to_string(port)+
        "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n";
    sendAll(fd,{request.begin(),request.end()});
    std::string response;
    while(!response.ends_with("\r\n\r\n")) {auto byte=readBytes(fd,1);response.push_back(static_cast<char>(byte[0]));assert(response.size()<4096);}
    assert(response.find("101 Switching Protocols")!=std::string::npos);
    assert(response.find("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")!=std::string::npos);
    return fd;
}
int main() {
    dkss::Config config;config.address="127.0.0.1";config.port=0;config.maxClients=1;config.token=std::string(64,'a');
    dkss::Metrics metrics;dkss::StreamServer server(config,"/nonexistent-test-assets",metrics,{});
    std::string error;assert(server.start(error));assert(server.localPort()!=0);
    int unauth=openWS(server.localPort());command(unauth,"{\"type\":\"ping\",\"t\":1}");
    auto denied=readFrame(unauth);assert(denied.first==8 && denied.second==std::vector<uint8_t>({3,240}));close(unauth);
    int first=openWS(server.localPort());
    command(first,"{\"type\":\"auth\",\"token\":\""+std::string(64,'a')+"\"}");
    auto ready=readFrame(first);assert(ready.first==1);assert(std::string(ready.second.begin(),ready.second.end()).find("\"viewOnly\":true")!=std::string::npos);
    assert(server.viewers()==1);
    int second=openWS(server.localPort());
    command(second,"{\"type\":\"auth\",\"token\":\""+std::string(64,'a')+"\"}");
    auto full=readFrame(second);assert(full.first==8 && full.second==std::vector<uint8_t>({3,245}));close(second);
    std::vector<uint8_t> jpeg{0xff,0xd8,0xff,0xd9};
    server.publish({1,123,1,1,4,0},jpeg);auto video=readFrame(first);
    assert(video.first==2 && video.second.size()==44 && video.second[0]=='D');
    int wrong=openWS(server.localPort());command(wrong,"{\"type\":\"auth\",\"token\":\"wrong\"}");
    assert(readFrame(wrong).first==8);close(wrong);assert(server.viewers()==1);
    command(first,"{\"type\":\"ping\",\"t\":123}");auto pong=readFrame(first);assert(pong.first==1);
    command(first,"{\"type\":\"tap\"}");auto readonly=readFrame(first);assert(readonly.first==8);close(first);
    for(unsigned attempt=0;attempt<100 && server.viewers();++attempt) std::this_thread::sleep_for(std::chrono::milliseconds(10));
    assert(server.viewers()==0);server.stop();assert(!server.healthy());
    std::cout<<"PASS: real RFC handshake, required auth, viewer limit, JPEG envelope, failed-client isolation, input rejection, cleanup\n";
}
