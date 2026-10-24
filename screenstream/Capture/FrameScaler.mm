// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#include "FrameScaler.h"
#import <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <cstring>

bool dkss::FrameScaler::copy(IOSurfaceRef surface,double scale,uint32_t maximum,uint16_t rotation,RawFrame &out) {
    if(!surface || !std::isfinite(scale) || scale<0.1 || scale>1 || maximum<64 || maximum>2048 ||
       (rotation!=0 && rotation!=90 && rotation!=180 && rotation!=270)) return false;
    const size_t w=IOSurfaceGetWidth(surface),h=IOSurfaceGetHeight(surface),stride=IOSurfaceGetBytesPerRow(surface);
    if(!w || !h || w>4096 || h>4096 || stride<w*4 || IOSurfaceGetAllocSize(surface)<stride*h) return false;
    double ratio=std::min(scale,double(maximum)/double(std::max(w,h)));
    size_t dw=std::max(size_t(1),size_t(std::lround(double(w)*ratio)));
    size_t dh=std::max(size_t(1),size_t(std::lround(double(h)*ratio)));
    out.width=static_cast<uint32_t>((rotation==90 || rotation==270)?dh:dw);
    out.height=static_cast<uint32_t>((rotation==90 || rotation==270)?dw:dh);
    out.orientation=rotation; out.pixels.resize(dw*dh*4);
    if(rotation) scratch.resize(out.pixels.size());
    constexpr uint32_t readOnlyLock=1;
    if(IOSurfaceLock(surface,readOnlyLock,nullptr)!=0) return false;
    auto *source=static_cast<uint8_t *>(IOSurfaceGetBaseAddress(surface));
    if(!source) { IOSurfaceUnlock(surface,readOnlyLock,nullptr); return false; }
    uint8_t *destination=rotation?scratch.data():out.pixels.data();
    vImage_Buffer input{source,h,w,stride},output{destination,dh,dw,dw*4};
    bool ok=true;
    if(w==dw && h==dh) {
        for(size_t row=0;row<h;++row) std::memcpy(destination+row*dw*4,source+row*stride,dw*4);
    } else {
        if(w!=sourceW || h!=sourceH || dw!=destW || dh!=destH) {
            vImage_Error needed=vImageScale_ARGB8888(&input,&output,nullptr,kvImageGetTempBufferSize);
            if(needed<0) ok=false;
            else {
                workspace.resize(std::max(size_t(1),static_cast<size_t>(needed)));
                sourceW=w; sourceH=h; destW=dw; destH=dh;
            }
        }
        if(ok) ok=vImageScale_ARGB8888(&input,&output,workspace.data(),kvImageNoFlags)==kvImageNoError;
    }
    IOSurfaceUnlock(surface,readOnlyLock,nullptr);
    if(ok && rotation) {
        vImage_Buffer rotated{out.pixels.data(),out.height,out.width,size_t(out.width)*4};
        uint8_t fill[4]={0,0,0,255};
        uint8_t code=rotation==90?kRotate90DegreesClockwise:rotation==180?kRotate180DegreesClockwise:kRotate270DegreesClockwise;
        ok=vImageRotate90_ARGB8888(&output,&rotated,code,fill,kvImageNoFlags)==kvImageNoError;
    }
    return ok;
}
void dkss::FrameScaler::clear() {
    scratch.clear(); scratch.shrink_to_fit(); workspace.clear(); workspace.shrink_to_fit();
    sourceW=sourceH=destW=destH=0;
}
