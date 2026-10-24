// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
// Uses the CoreAnimation/IOSurface capture API also documented by the GPL
// TrollVNC capture engine. Independent lifecycle; no FarmBIOS code or hooks.
#import "NativeCapture.h"
#include "FrameScaler.h"
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#include <cmath>

@interface UIScreen (DKSSNativeBounds)
- (CGRect)_unjailedReferenceBoundsInPixels;
@end
extern "C" {
    CFIndex CARenderServerGetDirtyFrameCount(void *);
    void CARenderServerRenderDisplay(kern_return_t,CFStringRef,IOSurfaceRef,int,int);
}

@implementation DKSSNativeCapture {
    IOSurfaceRef _render,_surface;
    IOSurfaceAcceleratorRef _accelerator;
    CFRunLoopSourceRef _runLoopSource;
    CFIndex _dirty;
    BOOL _hasFrame;
    BOOL _failed;
    dkss::FrameScaler _scaler;
}
- (BOOL)prepare {
    if(_surface) return YES;
    CGRect bounds=UIScreen.mainScreen._unjailedReferenceBoundsInPixels;
    size_t width=static_cast<size_t>(std::lround(bounds.size.width));
    size_t height=static_cast<size_t>(std::lround(bounds.size.height));
    if(!width || !height || width>4096 || height>4096) return NO;
    size_t row=IOSurfaceAlignProperty(kIOSurfaceBytesPerRow,width*4);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFPropertyListRef colorData=CGColorSpaceCopyPropertyList(color); CGColorSpaceRelease(color);
    NSDictionary *properties=@{(__bridge NSString *)kIOSurfaceWidth:@(width),
        (__bridge NSString *)kIOSurfaceHeight:@(height),(__bridge NSString *)kIOSurfaceBytesPerElement:@4,
        (__bridge NSString *)kIOSurfaceBytesPerRow:@(row),(__bridge NSString *)kIOSurfaceAllocSize:@(row*height),
        (__bridge NSString *)kIOSurfacePixelFormat:@(0x42475241),
        (__bridge NSString *)kIOSurfaceColorSpace:CFBridgingRelease(colorData)};
    _render=IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    _surface=IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if(!_render || !_surface || IOSurfaceAcceleratorCreate(kCFAllocatorDefault,nullptr,&_accelerator)!=0 || !_accelerator) {
        [self close]; return NO;
    }
    _runLoopSource=IOSurfaceAcceleratorGetRunLoopSource(_accelerator);
    if(_runLoopSource) CFRunLoopAddSource(CFRunLoopGetMain(),_runLoopSource,kCFRunLoopCommonModes);
    _hasFrame=NO; return YES;
}
- (BOOL)capture:(dkss::RawFrame &)frame scale:(double)scale maximum:(uint32_t)maximum rotation:(uint16_t)rotation force:(BOOL)force {
    NSAssert(NSThread.isMainThread,@"capture must run on main thread");
    _failed=NO;
    if(![self prepare]) { _failed=YES; return NO; }
    CFIndex dirty=CARenderServerGetDirtyFrameCount(nullptr);
    if(_hasFrame && !force && dirty==_dirty) return NO;
    CARenderServerRenderDisplay(0,CFSTR("LCD"),_render,0,0);
    if(IOSurfaceAcceleratorTransferSurface(_accelerator,_render,_surface,nullptr,nullptr,nullptr,nullptr)!=0) { _failed=YES; return NO; }
    if(!_scaler.copy(_surface,scale,maximum,rotation,frame)) { _failed=YES; return NO; }
    _dirty=dirty; _hasFrame=YES; return YES;
}
- (void)close {
    if(_runLoopSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(),_runLoopSource,kCFRunLoopCommonModes); _runLoopSource=nullptr; }
    if(_accelerator) { CFRelease(_accelerator); _accelerator=nullptr; }
    if(_surface) { CFRelease(_surface); _surface=nullptr; }
    if(_render) { CFRelease(_render); _render=nullptr; }
    _scaler.clear(); _hasFrame=NO;
}
- (void)dealloc { [self close]; }
- (BOOL)failed { return _failed; }
@end
