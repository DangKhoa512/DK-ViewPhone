// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <Foundation/Foundation.h>
void DKStartRuntime(void);
void DKConfigureLatencyMode(bool enabled);
void DKFrameCompleted(double milliseconds);
void DKUpdateBegin(void *client, int socket);
void DKUpdateEnd(void *client, bool success);
void DKClientDelta(int delta);
void DKRequestTermination(void);
bool DKTerminationRequested(void);
