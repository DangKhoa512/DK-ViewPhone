// GPL-2.0-only. Exact framebuffer damage, padding, and exhaustive small-image checks.
#include "../src/DKFrameDamage.h"
#include <algorithm>
#include <cassert>
#include <iostream>
#include <random>
#include <vector>

using dkviewphone::FrameDamage;

static bool same(FrameDamage a, FrameDamage b) {
    return (a.empty() && b.empty()) ||
        (a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom);
}

static FrameDamage reference(const std::vector<uint8_t> &a, const std::vector<uint8_t> &b,
                             int width, int height, size_t stride) {
    FrameDamage result{width, height, 0, 0};
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        const size_t pixel = static_cast<size_t>(y) * stride + static_cast<size_t>(x) * 4;
        bool changed = false;
        for (int channel = 0; channel < 4; ++channel) changed |= a[pixel + channel] != b[pixel + channel];
        if (!changed) continue;
        result.left = std::min(result.left, x); result.right = std::max(result.right, x + 1);
        result.top = std::min(result.top, y); result.bottom = std::max(result.bottom, y + 1);
    }
    return result;
}

static void replayPublication() {
    constexpr int width = 8, height = 6;
    constexpr size_t stride = width * 4;
    std::vector<uint8_t> front(stride * height, 0), back = front, desired = front;
    struct Viewer {
        std::vector<uint8_t> pixels, pending;
        Viewer(size_t bytes, size_t pixelsCount) : pixels(bytes, 0), pending(pixelsCount, 0) {}
    };
    Viewer fast(front.size(), width * height), slow(front.size(), width * height);
    int swaps = 0;
    auto publish = [&] {
        auto dirty = dkviewphone::changedBoundsRGBA32(front.data(), back.data(), width, height, stride);
        if (dirty.empty()) return;
        std::swap(front, back); ++swaps;
        // LibVNCServer accumulates pending damage for each client until sent.
        // A pixel mask is a simple independent oracle for that union behavior.
        for (auto *viewer : {&fast, &slow})
            for (int y = dirty.top; y < dirty.bottom; ++y)
                for (int x = dirty.left; x < dirty.right; ++x) viewer->pending[y * width + x] = 1;
    };
    auto drain = [&](Viewer &viewer) {
        for (size_t pixel = 0; pixel < viewer.pending.size(); ++pixel) {
            if (!viewer.pending[pixel]) continue;
            std::copy_n(front.data() + pixel * 4, 4, viewer.pixels.data() + pixel * 4);
        }
        std::fill(viewer.pending.begin(), viewer.pending.end(), 0);
        assert(viewer.pixels == front);
    };
    auto change = [&](int x, int y, uint8_t value) { desired[y * stride + x * 4] = value; };
    change(1, 1, 1); back = desired; publish(); drain(fast);
    change(1, 1, 0); change(6, 4, 1); back = desired; publish(); drain(fast);
    back = desired; publish(); assert(swaps == 2); // Identical capture keeps client damage.
    drain(slow);
    change(7, 0, 1); back = desired; publish(); // Two publications before either viewer sends.
    change(7, 0, 0); change(0, 5, 1); back = desired; publish(); drain(slow); drain(fast);
    change(3, 2, 1); back = desired; // Encoder contention: this back buffer never publishes.
    change(3, 2, 0); change(4, 3, 1); back = desired; publish();
    drain(fast); drain(slow);
    assert(front == desired && swaps == 5);
}

int main() {
    constexpr int width = 7, height = 5;
    constexpr size_t stride = width * 4 + 11;
    std::vector<uint8_t> a(stride * height, 0), b = a;
    auto bounds = [&] { return dkviewphone::changedBoundsRGBA32(a.data(), b.data(), width, height, stride); };
    auto change = [&](int x, int y, int channel = 0) { b[y * stride + x * 4 + channel] ^= 1; };
    assert(bounds().empty());
    // Bytes outside the pixels are not VNC framebuffer changes.
    for (int y = 0; y < height; ++y) b[y * stride + width * 4 + y] = 0xff;
    assert(bounds().empty());
    change(3, 2, 3); // Even an alpha-only difference must be detected exactly.
    assert(same(bounds(), {3, 2, 4, 3}));
    change(1, 1); change(5, 3);
    assert(same(bounds(), {1, 1, 6, 4}));
    change(0, 0); change(width - 1, height - 1);
    assert(same(bounds(), {0, 0, width, height}));

    // Every possible changed-pixel set in a 4x3 image: no hash collisions,
    // rectangle-count truncation, or omitted distant/corner changes.
    for (unsigned mask = 0; mask < (1u << 12); ++mask) {
        std::vector<uint8_t> before(4 * 3 * 4, 0), after = before;
        for (unsigned pixel = 0; pixel < 12; ++pixel)
            if (mask & (1u << pixel)) after[pixel * 4 + pixel % 4] = 1;
        assert(same(dkviewphone::changedBoundsRGBA32(before.data(), after.data(), 4, 3, 16),
                    reference(before, after, 4, 3, 16)));
    }
    // Random data checks different dimensions, stride, byte channels and sparsity.
    std::mt19937 random(20261019);
    for (int run = 0; run < 2000; ++run) {
        const int w = 1 + random() % 67, h = 1 + random() % 41;
        const size_t row = static_cast<size_t>(w) * 4 + random() % 17;
        std::vector<uint8_t> before(row * h), after;
        for (auto &value : before) value = static_cast<uint8_t>(random());
        after = before;
        for (unsigned count = random() % 60; count > 0; --count) after[random() % after.size()] ^= 1;
        assert(same(dkviewphone::changedBoundsRGBA32(before.data(), after.data(), w, h, row),
                    reference(before, after, w, h, row)));
    }
    assert(dkviewphone::changedBoundsRGBA32(nullptr, nullptr, 0, 5, 0).empty());
    assert(dkviewphone::changedBoundsRGBA32(nullptr, nullptr, 5, -1, 0).empty());
    assert(same(dkviewphone::changedBoundsRGBA32(nullptr, a.data(), width, height, stride), {0, 0, width, height}));
    assert(same(dkviewphone::changedBoundsRGBA32(a.data(), b.data(), width, height, 1), {0, 0, width, height}));
    assert(same(dkviewphone::changedBoundsRGBA32(a.data(), b.data(), width, height,
                                               std::numeric_limits<size_t>::max()), {0, 0, width, height}));
    replayPublication();
    std::cout << "PASS: exact bounds, alpha, padding, corners, 4096 masks, 2000 random images, guards, alternating buffers, lagging viewers, reverted and replaced frames\n";
}
