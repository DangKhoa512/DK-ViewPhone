// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

namespace dkviewphone {
// Exclusive right/bottom bounds in output framebuffer coordinates.
struct FrameDamage {
    int left = 0, top = 0, right = 0, bottom = 0;
    bool empty() const { return left >= right || top >= bottom; }
};

// Compare stable 32-bit output buffers, including every byte of every pixel.
// Unlike a sparse hash, this cannot omit a changed pixel or two distant changes.
// Row padding is ignored. The caller retains both buffers for this call and must
// prevent writes to either one while comparing (native publication does so under
// its sender locks). An unusable positive geometry is conservatively full damage.
inline FrameDamage changedBoundsRGBA32(const void *front, const void *back, int width, int height,
                                       size_t rowBytes) {
    if (width <= 0 || height <= 0) return {};
    const FrameDamage full{0, 0, width, height};
    const size_t limit = std::numeric_limits<size_t>::max();
    if (static_cast<size_t>(width) > limit / 4) return full;
    const size_t pixelBytes = static_cast<size_t>(width) * 4;
    if (!front || !back || rowBytes < pixelBytes ||
        (height > 1 && rowBytes > (limit - pixelBytes) / static_cast<size_t>(height - 1))) return full;
    const auto *a = static_cast<const uint8_t *>(front);
    const auto *b = static_cast<const uint8_t *>(back);

    int top = 0;
    while (top < height && std::memcmp(a + static_cast<size_t>(top) * rowBytes,
                                      b + static_cast<size_t>(top) * rowBytes, pixelBytes) == 0) ++top;
    if (top == height) return {};
    int bottom = height;
    while (bottom > top + 1 && std::memcmp(a + static_cast<size_t>(bottom - 1) * rowBytes,
                                          b + static_cast<size_t>(bottom - 1) * rowBytes, pixelBytes) == 0) --bottom;

    int left = width, right = 0;
    for (int y = top; y < bottom; ++y) {
        const auto *rowA = a + static_cast<size_t>(y) * rowBytes;
        const auto *rowB = b + static_cast<size_t>(y) * rowBytes;
        // Pixels already inside the accumulated rectangle cannot expand it.
        for (int x = 0; x < left; ++x) {
            const size_t offset = static_cast<size_t>(x) * 4;
            if (std::memcmp(rowA + offset, rowB + offset, 4) != 0) { left = x; break; }
        }
        for (int x = width; x > right; --x) {
            const size_t offset = static_cast<size_t>(x - 1) * 4;
            if (std::memcmp(rowA + offset, rowB + offset, 4) != 0) { right = x; break; }
        }
        if (left == 0 && right == width) break;
    }
    return {left, top, right, bottom};
}
}
