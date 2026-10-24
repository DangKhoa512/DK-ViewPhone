// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <Foundation/Foundation.h>
#include "../Common/Config.h"

@interface DKSSController : NSObject
- (instancetype)initWithConfig:(dkss::Config)config webRoot:(NSString *)webRoot;
- (BOOL)start;
- (void)stop;
- (NSDictionary *)metrics;
- (BOOL)healthy;
@end
