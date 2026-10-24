// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#include "../Common/Frame.h"
#include <vector>

namespace dkss {
// Synchronous on the dedicated encoder thread; RawFrame remains immutable.
std::vector<uint8_t> encodeJPEG(const RawFrame &frame,double quality);
}
