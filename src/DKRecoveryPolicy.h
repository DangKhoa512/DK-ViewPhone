// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include <algorithm>
#include <cstdint>

namespace dkviewphone {
// Wall time persists the budget across supervisor restarts. Deadlines within a
// running process use monotonic time; neither frame count nor Wi-Fi enters this policy.
struct RecoveryBudget {
    static constexpr unsigned limit = 5;
    static constexpr double windowSeconds = 900;
    unsigned failures = 0;
    uint64_t restarts = 0;
    double windowStart = 0, retryAt = 0;
    bool latched = false;

    double fail(double now) {
        if (!latched && (now < windowStart || now - windowStart >= windowSeconds)) {
            failures = 0;
            windowStart = now;
        }
        if (!failures) windowStart = now;
        ++failures;
        if (failures >= limit) { latched = true; retryAt = 0; return -1; }
        double delay = std::min(60.0, double(2u << std::min(failures - 1, 5u)));
        retryAt = now + delay;
        return delay;
    }
    bool canStart(double now) const { return !latched && now >= retryAt; }
    void manualOff() { failures = 0; windowStart = retryAt = 0; latched = false; }
};
}
