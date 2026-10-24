// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <IOSurface/IOSurface.h>
#include "../Common/Frame.h"

namespace dkss {
class FrameScaler {
    std::vector<uint8_t> scratch,workspace;
    size_t sourceW=0,sourceH=0,destW=0,destH=0;
public:
    bool copy(IOSurfaceRef surface,double scale,uint32_t maximum,uint16_t rotation,RawFrame &out);
    void clear();
};
}
