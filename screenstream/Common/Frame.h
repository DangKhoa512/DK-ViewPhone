// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <atomic>
#include <cstdint>
#include <vector>

namespace dkss {
struct RawFrame {
    uint32_t width=0,height=0;
    uint16_t orientation=0;
    uint64_t capturedMicros=0;
    double captureMs=0;
    std::vector<uint8_t> pixels;
};
struct Metrics {
    std::atomic<uint64_t> captured{0},encoded{0},skipped{0},dropped{0},encodeErrors{0},captureErrors{0};
    std::atomic<uint64_t> captureMicros{0},encodeMicros{0},outputBytes{0},socketBytes{0};
};
}
