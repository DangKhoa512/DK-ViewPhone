// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "../Common/Preferences.h"
#include <notify.h>

@interface DKSSPrefsController : PSListController
@end
@implementation DKSSPrefsController {
    NSUserDefaults *_defaults;
}
- (instancetype)init {
    if((self=[super init])) {
        _defaults=[[NSUserDefaults alloc] initWithSuiteName:DKSS_DOMAIN];
        [_defaults registerDefaults:@{@"Enabled":@NO,@"Preset":@"balanced",@"BindHost":@"auto",
            @"Quality":@"0.70",@"MaxDimension":@"1024",@"MaxClients":@"4"}];
        [self ensureToken];
    }
    return self;
}
- (NSArray *)specifiers {
    if(!_specifiers) _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (BOOL)ensureToken {
    NSString *existing=[_defaults stringForKey:@"Token"];
    if(dkss::validToken(existing.UTF8String ?: "")) return YES;
    uint8_t random[32]; if(SecRandomCopyBytes(kSecRandomDefault,sizeof(random),random)!=errSecSuccess) return NO;
    NSMutableString *value=[NSMutableString stringWithCapacity:64];
    for(uint8_t byte:random) [value appendFormat:@"%02x",byte];
    [_defaults setObject:value forKey:@"Token"]; [_defaults synchronize];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600}
        ofItemAtPath:@"/var/mobile/Library/Preferences/com.dk.screenstream.plist" error:nil];
    return YES;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [_defaults objectForKey:[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)showError:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"ĐK ScreenStream" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if([key isEqual:@"BindHost"]) {
        NSString *bind=[value isKindOfClass:NSString.class]?[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:@"";
        in_addr address{};
        if(!DKBindHostIsAutomatic(bind.UTF8String) &&
           (inet_pton(AF_INET,bind.UTF8String,&address)!=1 ||
            !(DKLANPrivateIPv4(ntohl(address.s_addr)) || (ntohl(address.s_addr)>>24)==127))) {
            [self showError:@"Nhập auto, IPv4 LAN của iPhone hoặc 127.0.0.1."]; return;
        }
        value=bind.length?bind:@"auto";
    }
    NSDictionary *ranges=@{@"Quality":@[@0.1,@0.95],@"MaxDimension":@[@256,@2048],
        @"MaxClients":@[@1,@4],@"CustomScale":@[@0.1,@1.0],@"CustomFPS":@[@1,@30]};
    if(ranges[key] && [value isKindOfClass:NSString.class] && [value length]) {
        NSScanner *scanner=[NSScanner scannerWithString:value]; double number=0;
        if(![scanner scanDouble:&number] || !scanner.isAtEnd || !std::isfinite(number) ||
           number<[ranges[key][0] doubleValue] || number>[ranges[key][1] doubleValue]) {
            [self showError:@"Giá trị nằm ngoài phạm vi cho phép."]; return;
        }
    }
    if([key isEqual:@"Enabled"] && [value boolValue] && ![self ensureToken]) {
        [self showError:@"Không tạo được mã kết nối. Máy chủ vẫn đang tắt."]; return;
    }
    if(value) [_defaults setObject:value forKey:key]; else [_defaults removeObjectForKey:key];
    [_defaults synchronize]; notify_post(DKSS_NOTIFY);
}
- (NSString *)streamURL:(PSSpecifier *)specifier {
    (void)specifier;
    auto config=DKSSConfig(DKSSReadPreferences());
    return [NSString stringWithFormat:@"http://%s:%u/",config.address.c_str(),config.port];
}
- (void)copyToken {
    if([self ensureToken]) UIPasteboard.generalPasteboard.string=[_defaults stringForKey:@"Token"];
}
- (void)rotateToken {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Đổi mã kết nối?"
        message:@"Các phiên xem hiện tại sẽ ngắt. Bạn cần nhập mã mới trên máy tính." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đổi mã" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action; [self->_defaults removeObjectForKey:@"Token"];
        if([self ensureToken]) notify_post(DKSS_NOTIFY); else [self showError:@"Không tạo được mã mới."];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
