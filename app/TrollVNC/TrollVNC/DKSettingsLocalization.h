// GPL-2.0-only. Vietnamese UI without changing system language or preference keys.
#pragma once
#import <Foundation/Foundation.h>

NS_INLINE NSString *DKSettingsLocalizedString(NSString *key, NSString *table,
                                              NSBundle *bundle, NSString *comment) {
    (void)comment;
    NSString *path = [bundle pathForResource:@"vi" ofType:@"lproj"];
    NSBundle *vietnamese = path ? [NSBundle bundleWithPath:path] : nil;
    return [(vietnamese ?: bundle) localizedStringForKey:key value:key table:table];
}
