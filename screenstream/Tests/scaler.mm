// GPL-2.0-only. Real IOSurface/vImage round trip with known pixel positions.
#include "../Capture/FrameScaler.h"
#import <Foundation/Foundation.h>
#include <cassert>
#include <iostream>

int main() { @autoreleasepool {
    const size_t stride=IOSurfaceAlignProperty(kIOSurfaceBytesPerRow,16);
    NSDictionary *properties=@{(__bridge NSString *)kIOSurfaceWidth:@4,
        (__bridge NSString *)kIOSurfaceHeight:@2,(__bridge NSString *)kIOSurfaceBytesPerElement:@4,
        (__bridge NSString *)kIOSurfaceBytesPerRow:@(stride),(__bridge NSString *)kIOSurfaceAllocSize:@(stride*2),
        (__bridge NSString *)kIOSurfacePixelFormat:@(0x42475241)};
    IOSurfaceRef surface=IOSurfaceCreate((__bridge CFDictionaryRef)properties);assert(surface);
    assert(!IOSurfaceLock(surface,0,nullptr));auto *bytes=static_cast<uint8_t *>(IOSurfaceGetBaseAddress(surface));assert(bytes);
    for(size_t y=0;y<2;++y)for(size_t x=0;x<4;++x){auto *p=bytes+y*stride+x*4;p[0]=static_cast<uint8_t>(y*4+x+1);p[1]=p[2]=0;p[3]=255;}
    IOSurfaceUnlock(surface,0,nullptr);
    dkss::FrameScaler scaler;dkss::RawFrame frame;
    for(auto rotation:{0,90,180,270}) {
        assert(scaler.copy(surface,1,64,rotation,frame));
        assert(frame.width==unsigned(rotation==90||rotation==270?2:4));
        assert(frame.height==unsigned(rotation==90||rotation==270?4:2));
        const uint8_t expected[4][8]={{1,2,3,4,5,6,7,8},{5,1,6,2,7,3,8,4},{8,7,6,5,4,3,2,1},{4,8,3,7,2,6,1,5}};
        for(size_t i=0;i<8;++i)assert(frame.pixels[i*4]==expected[rotation/90][i]);
    }
    assert(scaler.copy(surface,.5,64,0,frame));assert(frame.width==2&&frame.height==1);
    assert(!scaler.copy(surface,0,64,0,frame));assert(!scaler.copy(surface,1,64,45,frame));
    scaler.clear();CFRelease(surface);
    std::cout<<"PASS: IOSurface lock/stride, scale, four pixel rotations and invalid inputs\n";
} }
