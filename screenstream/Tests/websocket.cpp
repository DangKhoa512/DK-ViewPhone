// GPL-2.0-only. Masking, fragmented input and partial output byte ordering.
#include "../Streaming/WebSocket.h"
#include <cassert>
#include <iostream>
#include <string>

static dkss::Bytes masked(uint8_t opcode,std::string payload,bool fin=true) {
    assert(payload.size()<126);
    dkss::Bytes frame{static_cast<uint8_t>((fin?0x80:0)|opcode),static_cast<uint8_t>(0x80|payload.size()),1,2,3,4};
    for(size_t i=0;i<payload.size();++i) frame.push_back(payload[i]^frame[2+i%4]);
    return frame;
}
int main() {
    dkss::WebSocketParser parser;
    auto text=masked(1,"authenticate");
    for(size_t i=0;i<text.size();++i) {
        assert(parser.append(std::span(text).subspan(i,1)));
        auto message=parser.next();
        if(i+1<text.size()) assert(!message);
        else assert(message && std::string(message->data.begin(),message->data.end())=="authenticate");
    }
    auto fragment=masked(1,"hello",false), ping=masked(9,"ping"), end=masked(0,"world");
    assert(parser.append(fragment)); assert(!parser.next());
    assert(parser.append(ping)); assert(parser.next()->opcode==9);
    assert(parser.append(end)); auto message=parser.next();
    assert(message && std::string(message->data.begin(),message->data.end())=="helloworld");
    for(auto invalid : {dkss::Bytes{0x81,0},dkss::Bytes{0xc1,0x80},dkss::Bytes{0x09,0x80},
                       dkss::Bytes{0x88,0x81},dkss::Bytes{0x83,0x80}}) {
        dkss::WebSocketParser bad; bad.append(invalid); bad.next(); assert(bad.error()==1002);
    }
    dkss::WebSocketParser large;
    dkss::Bytes oversized{0x81,0xfe,0x20,0x00}; large.append(oversized); large.next(); assert(large.error()==1009);
    dkss::WebSocketParser continuation; continuation.append(masked(0,"bad")); continuation.next(); assert(continuation.error()==1002);
    auto packet=[](std::string value) { return dkss::websocketPacket(2,std::span(reinterpret_cast<const uint8_t*>(value.data()),value.size())); };
    dkss::OutputQueue queue;
    auto a=packet("first frame"), b=packet("obsolete"), c=packet("latest frame");
    queue.latest(a); auto view=queue.bytes(); dkss::Bytes actual(view.begin(),view.begin()+3); queue.consumed(3);
    queue.latest(b); queue.latest(c); assert(queue.replaced==1);
    while(queue.pending()) { auto part=queue.bytes(); actual.push_back(part.front()); queue.consumed(1); }
    dkss::Bytes expected=*a; expected.insert(expected.end(),c->begin(),c->end()); assert(actual==expected);
    for(int n=0;n<8;++n) assert(queue.control(packet("control")));
    assert(!queue.control(packet("overflow")));
    std::cout << "PASS: masked/fragmented commands, malformed limits, partial writes, bounded controls\n";
}
