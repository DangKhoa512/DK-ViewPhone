// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <Foundation/Foundation.h>
BOOL DKSSPrepareLogDirectory(void);
void DKSSLog(NSString *event,NSDictionary *fields);
NSString *DKSSStatePath(void);
