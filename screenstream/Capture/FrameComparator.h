// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include "../Common/Frame.h"
#include <cstring>

namespace dkss {
// Encoder-thread only. Commit only after a JPEG was successfully produced.
class FrameComparator {
    std::vector<uint8_t> previous;
    uint32_t width=0,height=0;
    uint16_t orientation=0;
public:
    bool identical(const RawFrame &frame) const {
        return width==frame.width && height==frame.height && orientation==frame.orientation &&
            previous.size()==frame.pixels.size() && !previous.empty() &&
            std::memcmp(previous.data(),frame.pixels.data(),previous.size())==0;
    }
    void commit(const RawFrame &frame) {
        previous=frame.pixels; width=frame.width; height=frame.height; orientation=frame.orientation;
    }
    void clear() { previous.clear(); previous.shrink_to_fit(); width=height=orientation=0; }
};
}
