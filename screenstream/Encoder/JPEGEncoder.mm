// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#include "JPEGEncoder.h"
#include "../Common/Protocol.h"
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cmath>

std::vector<uint8_t> dkss::encodeJPEG(const RawFrame &frame,double quality) {
    if(!std::isfinite(quality) || quality<0.1 || quality>0.95 || !frame.width || !frame.height ||
       frame.width>2048 || frame.height>2048 || frame.pixels.size()!=size_t(frame.width)*frame.height*4) return {};
    // The provider does not own this memory; the encoder retains the RawFrame
    // through CGImageDestinationFinalize and releases the image before returning.
    CGDataProviderRef provider=CGDataProviderCreateWithData(nullptr,frame.pixels.data(),frame.pixels.size(),nullptr);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image=provider&&color?CGImageCreate(frame.width,frame.height,8,32,size_t(frame.width)*4,color,
        kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst,provider,nullptr,false,kCGRenderingIntentDefault):nullptr;
    if(provider) CGDataProviderRelease(provider);
    if(color) CGColorSpaceRelease(color);
    if(!image) return {};
    CFMutableDataRef data=CFDataCreateMutable(kCFAllocatorDefault,0);
    CGImageDestinationRef destination=data?CGImageDestinationCreateWithData(data,CFSTR("public.jpeg"),1,nullptr):nullptr;
    bool ok=false;
    if(destination) {
        NSDictionary *options=@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@(quality)};
        CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)options);
        ok=CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(image);
    std::vector<uint8_t> jpeg;
    if(ok && CFDataGetLength(data)>0 && static_cast<size_t>(CFDataGetLength(data))<=maxJPEGBytes)
        jpeg.assign(CFDataGetBytePtr(data),CFDataGetBytePtr(data)+CFDataGetLength(data));
    if(data) CFRelease(data);
    return jpeg;
}
