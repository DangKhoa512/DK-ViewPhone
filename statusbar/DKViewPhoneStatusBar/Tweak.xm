#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <objc/runtime.h>

static NSHashTable *DKModernTimeViews(void) {
    static NSHashTable *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}

static NSHashTable *DKLegacyTimeViews(void) {
    static NSHashTable *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}

static BOOL DKPrivateIPv4(uint32_t address) {
    return (address >> 24) == 10 || (address >> 16) == 0xa9fe ||
           (address >> 16) == 0xc0a8 || (address >= 0xac100000 && address <= 0xac1fffff);
}

static NSString *DKCurrentIPv4(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces)
        return @"IPv4 --";

    NSString *best = nil;
    NSInteger bestScore = -1;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET ||
            !(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK))
            continue;
        const struct sockaddr_in *address = (const struct sockaddr_in *)item->ifa_addr;
        uint32_t hostAddress = ntohl(address->sin_addr.s_addr);
        char buffer[INET_ADDRSTRLEN] = {0};
        if (!inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer)))
            continue;
        NSString *name = item->ifa_name ? [NSString stringWithUTF8String:item->ifa_name] : @"";
        NSInteger score = [name isEqualToString:@"en0"] ? 100 : (DKPrivateIPv4(hostAddress) ? 50 : 10);
        if (score > bestScore) {
            best = [NSString stringWithUTF8String:buffer];
            bestScore = score;
        }
    }
    freeifaddrs(interfaces);
    return best ?: @"IPv4 --";
}

@interface NSObject (DKViewPhoneStatusBarPrivate)
- (id)imageWithText:(NSString *)text;
- (void)updateContentsAndWidth;
- (id)timeView;
- (id)shortTimeView;
- (id)pillTimeView;
- (void)setText:(NSString *)text;
@end

// Non-notched devices such as the iPhone 6s render the clock as an image.
// Hooking this concrete class avoids changing carrier or date strings.
%hook UIStatusBarTimeItemView

- (id)contentsImage {
    [DKLegacyTimeViews() addObject:self];
    return [self imageWithText:DKCurrentIPv4()];
}

%end

// Newer status bars use string views owned by a dedicated time item. Update
// only the views returned by that item instead of globally replacing strings.
%hook _UIStatusBarTimeItem

- (void)applyUpdate:(id)update toDisplayItem:(id)displayItem {
    %orig;
    NSString *address = DKCurrentIPv4();
    for (id view in @[[self timeView] ?: NSNull.null,
                      [self shortTimeView] ?: NSNull.null,
                      [self pillTimeView] ?: NSNull.null]) {
        if (view != NSNull.null && [view respondsToSelector:@selector(setText:)]) {
            [DKModernTimeViews() addObject:view];
            [view setText:address];
        }
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(__unused NSTimer *timer) {
            NSString *address = DKCurrentIPv4();
            for (id view in DKModernTimeViews().allObjects)
                [view setText:address];
            for (id view in DKLegacyTimeViews().allObjects)
                [view updateContentsAndWidth];
        }];
    });
}
