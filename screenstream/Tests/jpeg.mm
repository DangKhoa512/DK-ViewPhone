// GPL-2.0-only. Exercise the actual platform JPEG encoder and decode dimensions.
#include "../Encoder/JPEGEncoder.h"
#import <ImageIO/ImageIO.h>
#import <Foundation/Foundation.h>
#include <cassert>
#include <iostream>

int main() { @autoreleasepool {
    dkss::RawFrame frame;frame.width=8;frame.height=4;frame.pixels.resize(8*4*4);
    for(size_t at=0;at<frame.pixels.size();at+=4) {frame.pixels[at+2]=255;frame.pixels[at+3]=255;}
    auto jpeg=dkss::encodeJPEG(frame,0.7);assert(jpeg.size()>4 && jpeg[0]==0xff && jpeg[1]==0xd8);
    NSData *data=[NSData dataWithBytes:jpeg.data() length:jpeg.size()];
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,nullptr);assert(source);
    CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,nullptr);assert(image);
    assert(CGImageGetWidth(image)==8 && CGImageGetHeight(image)==4);CGImageRelease(image);CFRelease(source);
    assert(dkss::encodeJPEG(frame,0.01).empty());frame.pixels.pop_back();assert(dkss::encodeJPEG(frame,0.7).empty());
    std::cout<<"PASS: ImageIO JPEG round trip, dimensions and invalid inputs\n";
} }
