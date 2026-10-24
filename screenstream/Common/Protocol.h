// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <vector>

namespace dkss {
constexpr uint8_t protocolVersion = 1;
constexpr size_t headerSize = 40;
constexpr size_t maxJPEGBytes = 4 * 1024 * 1024;
struct FrameInfo {
    uint64_t sequence = 0, monotonicMicros = 0;
    uint32_t width = 0, height = 0, jpegBytes = 0;
    uint16_t orientation = 0;
};
inline void put(std::span<uint8_t> out, size_t at, uint64_t value, size_t bytes) {
    if (bytes > 8 || at > out.size() || bytes > out.size() - at) throw std::out_of_range("header write");
    for (size_t n = 0; n < bytes; ++n) out[at + bytes - 1 - n] = static_cast<uint8_t>(value >> (n * 8));
}
inline uint64_t get(std::span<const uint8_t> in, size_t at, size_t bytes) {
    if (bytes > 8 || at > in.size() || bytes > in.size() - at) throw std::out_of_range("header read");
    uint64_t value = 0;
    for (size_t n = 0; n < bytes; ++n) value = value * 256 + in[at + n];
    return value;
}
inline bool valid(const FrameInfo &info) {
    return info.width && info.height && info.width <= 4096 && info.height <= 4096 &&
        info.jpegBytes && info.jpegBytes <= maxJPEGBytes &&
        (info.orientation == 0 || info.orientation == 90 || info.orientation == 180 || info.orientation == 270);
}
inline std::array<uint8_t, headerSize> encodeHeader(const FrameInfo &info) {
    if (!valid(info)) throw std::invalid_argument("invalid frame geometry or JPEG size");
    std::array<uint8_t, headerSize> out{};
    out[0]='D'; out[1]='K'; out[2]='S'; out[3]='S'; out[4]=protocolVersion; out[5]=1;
    put(out,6,headerSize,2); put(out,8,info.sequence,8); put(out,16,info.monotonicMicros,8);
    put(out,24,info.width,4); put(out,28,info.height,4); put(out,32,info.orientation,2);
    put(out,36,info.jpegBytes,4);
    return out;
}
inline bool decodeHeader(std::span<const uint8_t> in, FrameInfo &info) {
    if (in.size() < headerSize || in[0]!='D' || in[1]!='K' || in[2]!='S' || in[3]!='S' ||
        in[4]!=protocolVersion || in[5]!=1 || get(in,6,2)!=headerSize || get(in,34,2)!=0) return false;
    FrameInfo parsed{get(in,8,8),get(in,16,8),static_cast<uint32_t>(get(in,24,4)),
        static_cast<uint32_t>(get(in,28,4)),static_cast<uint32_t>(get(in,36,4)),
        static_cast<uint16_t>(get(in,32,2))};
    if (!valid(parsed)) return false;
    info=parsed; return true;
}
} // namespace dkss
