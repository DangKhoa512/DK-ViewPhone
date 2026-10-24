// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <cstdint>
#include <deque>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <vector>

namespace dkss {
using Bytes=std::vector<uint8_t>;
using Packet=std::shared_ptr<const Bytes>;
struct WebSocketMessage { uint8_t opcode=0; Bytes data; };
class WebSocketParser {
    Bytes buffered, fragmented;
    uint8_t fragmentOpcode=0;
    static constexpr size_t maximum=4096;
    uint16_t failure=0;
public:
    uint16_t error() const { return failure; }
    bool append(std::span<const uint8_t> bytes) {
        if(failure) return false;
        // Bound read-ahead separately from the per-message limit. The server
        // drains after each <=4096-byte socket read, including coalesced frames.
        if(bytes.size()>maximum || buffered.size()+bytes.size()>2*maximum+28) {
            failure=1009; return false;
        }
        buffered.insert(buffered.end(),bytes.begin(),bytes.end()); return true;
    }
    std::optional<WebSocketMessage> next() {
        if(failure || buffered.size()<2) return {};
        uint8_t first=buffered[0], second=buffered[1], opcode=first&15;
        bool fin=(first&0x80)!=0, control=opcode>=8;
        if((first&0x70) || !(second&0x80) ||
           (opcode!=0 && opcode!=1 && opcode!=2 && opcode!=8 && opcode!=9 && opcode!=10)) {
            failure=1002; return {};
        }
        uint64_t length=second&127; size_t at=2;
        if(length==126) {
            if(buffered.size()<4) return {};
            length=uint64_t(buffered[2])*256+buffered[3]; at=4;
            if(length<126) { failure=1002; return {}; }
        } else if(length==127) {
            if(buffered.size()<10) return {};
            length=0; for(size_t i=2;i<10;++i) length=length*256+buffered[i]; at=10;
            if(length<65536 || (buffered[2]&0x80)) { failure=1002; return {}; }
        }
        if(control && (!fin || length>125 || (opcode==8 && length==1))) { failure=1002; return {}; }
        if(length>maximum || (!control && fragmented.size()+length>maximum)) { failure=1009; return {}; }
        if(buffered.size()<at+4+length) return {};
        WebSocketMessage message; message.opcode=opcode; message.data.resize(static_cast<size_t>(length));
        for(size_t i=0;i<length;++i) message.data[i]=buffered[at+4+i]^buffered[at+i%4];
        buffered.erase(buffered.begin(),buffered.begin()+at+4+static_cast<size_t>(length));
        if(control) return message;
        if(opcode==0) {
            if(!fragmentOpcode) { failure=1002; return {}; }
            fragmented.insert(fragmented.end(),message.data.begin(),message.data.end());
            if(!fin) return next();
            message.opcode=fragmentOpcode; message.data=std::move(fragmented);
            fragmented.clear(); fragmentOpcode=0; return message;
        }
        if(fragmentOpcode) { failure=1002; return {}; }
        if(!fin) { fragmentOpcode=opcode; fragmented=std::move(message.data); return next(); }
        return message;
    }
};
inline Packet websocketPacket(uint8_t opcode,std::span<const uint8_t> body) {
    auto bytes=std::make_shared<Bytes>(); bytes->reserve(body.size()+10);
    bytes->push_back(0x80|opcode);
    if(body.size()<126) bytes->push_back(static_cast<uint8_t>(body.size()));
    else if(body.size()<=65535) {
        bytes->push_back(126); bytes->push_back(static_cast<uint8_t>(body.size()>>8)); bytes->push_back(static_cast<uint8_t>(body.size()));
    } else {
        bytes->push_back(127);
        for(int shift=56;shift>=0;shift-=8) bytes->push_back(static_cast<uint8_t>(uint64_t(body.size())>>shift));
    }
    bytes->insert(bytes->end(),body.begin(),body.end()); return bytes;
}
// An in-flight packet stays immutable. Keep only the newest pending video.
class OutputQueue {
    Packet current, video;
    std::deque<Packet> controls;
    size_t offset=0;
public:
    uint64_t replaced=0;
    bool control(Packet value) {
        if(controls.size()>=8) return false;
        controls.push_back(std::move(value)); return true;
    }
    void latest(Packet value) { if(video) ++replaced; video=std::move(value); }
    void discardPendingVideo() { video.reset(); }
    bool pending() const { return current || video || !controls.empty(); }
    std::span<const uint8_t> bytes() {
        if(!current) {
            if(!controls.empty()) { current=controls.front(); controls.pop_front(); }
            else { current=std::move(video); video.reset(); }
            offset=0;
        }
        return current ? std::span<const uint8_t>(*current).subspan(offset) : std::span<const uint8_t>{};
    }
    void consumed(size_t count) {
        if(!current || count>current->size()-offset) throw std::out_of_range("socket write progress");
        offset+=count;
        if(offset==current->size()) { current.reset(); offset=0; }
    }
};
} // namespace dkss
