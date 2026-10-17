// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
namespace dkviewphone {
template <typename Counter>
inline bool consumeClipboardEcho(bool sameValue, Counter &remaining) {
    if (remaining <= 0) return false;
    if (sameValue) { --remaining; return true; }
    // Some iOS versions deliver fewer notifications than the remote setter
    // anticipates. A different value is a new local change, never an echo.
    remaining = 0;
    return false;
}
}
