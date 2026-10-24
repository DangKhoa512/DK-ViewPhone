// GPL-2.0-only. Actual protocol byte vectors and bounded producer/consumer behavior.
#include "../Common/Protocol.h"
#include "../Streaming/LatestQueue.h"
#include "../Common/Config.h"
#include "../Capture/FrameComparator.h"
#include <cassert>
#include <future>
#include <iostream>
#include <thread>

int main() {
    dkss::FrameInfo info{0x0102030405060708ULL,123456789,750,1334,4096,90}, parsed;
    auto header=dkss::encodeHeader(info);
    assert(header[0]=='D' && header[4]==1 && header[7]==40 && header[8]==1 && header[15]==8);
    assert(dkss::decodeHeader(header,parsed));
    assert(parsed.width==750 && parsed.height==1334 && parsed.sequence==info.sequence && parsed.orientation==90);
    for (size_t length=0; length<dkss::headerSize; ++length)
        assert(!dkss::decodeHeader(std::span(header).first(length),parsed));
    for (size_t field : {size_t(0),size_t(4),size_t(5),size_t(7),size_t(34)}) {
        auto bad=header; bad[field]^=0xff; assert(!dkss::decodeHeader(bad,parsed));
    }
    auto bad=header; dkss::put(bad,36,dkss::maxJPEGBytes+1,4); assert(!dkss::decodeHeader(bad,parsed));
    bad=header; dkss::put(bad,24,0,4); assert(!dkss::decodeHeader(bad,parsed));
    bad=header; dkss::put(bad,32,45,2); assert(!dkss::decodeHeader(bad,parsed));
    dkss::LatestQueue<int> queue;
    assert(queue.push(1)==decltype(queue)::Push::accepted);
    for(int n=2;n<=100000;++n) assert(queue.push(n)==decltype(queue)::Push::replaced);
    assert(queue.take()==100000 && !queue.take());
    auto waiting=std::async(std::launch::async,[&] { return queue.wait(); });
    queue.close(); assert(!waiting.get());
    assert(queue.push(7)==decltype(queue)::Push::closed && !queue.take());
    dkss::LatestQueue<int> live;
    auto consumer=std::async(std::launch::async,[&] { return live.wait(); });
    live.push(42); assert(consumer.get()==42); live.close();
    assert(dkss::preset("low").fps==10 && dkss::preset("low").scale==0.5);
    assert(dkss::preset("balanced").fps==15 && dkss::preset("high").fps==20);
    assert(dkss::constantTimeToken(std::string(64,'a'),std::string(64,'a')));
    assert(!dkss::constantTimeToken(std::string(64,'a'),std::string(64,'b')));
    assert(!dkss::constantTimeToken(std::string(64,'a'),std::string(65,'a')));
    assert(!dkss::validToken("default"));
    dkss::RawFrame pixels; pixels.width=2; pixels.height=2; pixels.pixels.resize(16);
    dkss::FrameComparator comparator; assert(!comparator.identical(pixels));
    comparator.commit(pixels); assert(comparator.identical(pixels));
    pixels.pixels[15]=1; assert(!comparator.identical(pixels));
    pixels.pixels[15]=0; pixels.orientation=90; assert(!comparator.identical(pixels));
    std::cout << "PASS: DKSS byte vectors, truncated/malformed headers, latest-only bound, close wake-up\n";
}
