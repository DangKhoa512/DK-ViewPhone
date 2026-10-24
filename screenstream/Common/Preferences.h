// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#pragma once
#import <Foundation/Foundation.h>
#include "Config.h"
#include "NetworkAddress.h"
#include <algorithm>
#include <cmath>

#define DKSS_DOMAIN @"com.dk.screenstream"
#define DKSS_NOTIFY "com.dk.screenstream.prefs-changed"

static inline NSDictionary *DKSSReadPreferences(void) {
    CFStringRef domain=CFSTR("com.dk.screenstream");
    CFPreferencesSynchronize(domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    return CFBridgingRelease(CFPreferencesCopyMultiple(nullptr,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)) ?: @{};
}
static inline BOOL DKSSEnabled(NSDictionary *values) {
    id value=values[@"Enabled"];
    return ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) && [value boolValue];
}
static inline dkss::Config DKSSConfig(NSDictionary *values) {
    NSString *profile=[values[@"Preset"] isKindOfClass:NSString.class]?values[@"Preset"]:@"balanced";
    auto config=dkss::preset(profile.UTF8String ?: "balanced");
    NSString *bind=[values[@"BindHost"] isKindOfClass:NSString.class]?
        [values[@"BindHost"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:@"auto";
    if(DKBindHostIsAutomatic(bind.UTF8String)) {
        char address[INET_ADDRSTRLEN]; DKAutomaticLANIPv4(address); config.address=address;
    } else config.address=bind.UTF8String ?: "";
    if([values[@"Token"] isKindOfClass:NSString.class]) config.token=[values[@"Token"] UTF8String] ?: "";
    auto number=[&](NSString *key,double fallback) {
        id value=values[key];
        if(![value isKindOfClass:NSNumber.class] && ![value isKindOfClass:NSString.class]) return fallback;
        if([value isKindOfClass:NSString.class] && ![value length]) return fallback;
        double parsed=[value doubleValue]; return std::isfinite(parsed)?parsed:fallback;
    };
    config.quality=std::clamp(number(@"Quality",0.70),0.1,0.95);
    config.maxDimension=static_cast<unsigned>(std::clamp(number(@"MaxDimension",1024),256.0,2048.0));
    config.scale=std::clamp(number(@"CustomScale",config.scale),0.1,1.0);
    config.fps=static_cast<unsigned>(std::clamp(number(@"CustomFPS",config.fps),1.0,30.0));
    config.maxClients=static_cast<unsigned>(std::clamp(number(@"MaxClients",4),1.0,4.0));
    return config;
}
