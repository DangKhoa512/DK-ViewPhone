// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <cstdint>
#include <string>

namespace dkss {
struct Config {
    std::string address="127.0.0.1",token;
    uint16_t port=5802;
    unsigned fps=15,maxDimension=1024,maxClients=4;
    double scale=0.65,quality=0.70;
};
inline Config preset(const std::string &name) {
    Config result;
    if(name=="low") { result.scale=0.5; result.fps=10; }
    else if(name=="high") { result.scale=0.75; result.fps=20; }
    return result;
}
inline bool validToken(const std::string &token) {
    if(token.size()!=64) return false;
    for(unsigned char c:token) if(!((c>='0'&&c<='9')||(c>='a'&&c<='f'))) return false;
    return true;
}
inline bool constantTimeToken(const std::string &expected,const std::string &provided) {
    if(!validToken(expected) || provided.size()!=expected.size()) return false;
    unsigned different=0;
    for(size_t i=0;i<expected.size();++i) different|=static_cast<unsigned char>(expected[i])^static_cast<unsigned char>(provided[i]);
    return different==0;
}
}
