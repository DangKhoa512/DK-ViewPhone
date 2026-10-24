// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <chrono>
#include <cstdint>
namespace dkss {
inline uint64_t nowMicros() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
inline double nowSeconds() { return double(nowMicros())/1e6; }
}
