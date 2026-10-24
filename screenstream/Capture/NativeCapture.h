// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <Foundation/Foundation.h>
#include "../Common/Frame.h"

@interface DKSSNativeCapture : NSObject
// Main-thread only. Caller provides a frame not held by the encoder/pending queue.
- (BOOL)capture:(dkss::RawFrame &)frame scale:(double)scale maximum:(uint32_t)maximum rotation:(uint16_t)rotation force:(BOOL)force;
@property(nonatomic,readonly) BOOL failed;
- (void)close;
@end
