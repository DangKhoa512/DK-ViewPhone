#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <objc/runtime.h>

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

// UIStatusBarTimeItemView inherits dateTimeString from
// UIStatusBarDateTimeItemView on iOS 15. Hook the class which actually owns the
// getter, then limit the replacement to time items so date views remain intact.
// UIKit continues to own all image/cache/layout work; calling private rendering
// methods from the tweak can recurse on iOS 15.8.4.
%hook UIStatusBarDateTimeItemView

- (NSString *)dateTimeString {
    Class timeItemClass = objc_getClass("UIStatusBarTimeItemView");
    if (timeItemClass && [(id)self isKindOfClass:timeItemClass])
        return DKCurrentIPv4();
    return %orig;
}

- (void)setDateTimeString:(NSString *)text {
    Class timeItemClass = objc_getClass("UIStatusBarTimeItemView");
    if (timeItemClass && [(id)self isKindOfClass:timeItemClass]) {
        %orig(DKCurrentIPv4());
        return;
    }
    %orig(text);
}

%end
