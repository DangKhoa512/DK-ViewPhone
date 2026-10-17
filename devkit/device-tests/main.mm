// Temporary device test executable, GPL-2.0-only. Never included in the DEB.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <unistd.h>
#import <vector>

static NSString *ipv4() {
    NSString *result = nil; struct ifaddrs *addresses = NULL;
    if (!getifaddrs(&addresses)) {
        for (auto *a = addresses; a; a = a->ifa_next) {
            if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET || strcmp(a->ifa_name,"en0")) continue;
            char buffer[INET_ADDRSTRLEN];
            if (inet_ntop(AF_INET,&((struct sockaddr_in *)a->ifa_addr)->sin_addr,buffer,sizeof(buffer))) result = @(buffer);
        }
        freeifaddrs(addresses);
    }
    return result;
}
static void pump(double seconds) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,false); }
static void printJSON(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    if (data) { fwrite(data.bytes,1,data.length,stdout); puts(""); fflush(stdout); }
}
static int wifi(NSString *mode) {
    void *library = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi",RTLD_NOW);
    if (!library) return 2;
    auto create = (CFTypeRef (*)(CFAllocatorRef,int))dlsym(library,"WiFiManagerClientCreate");
    auto schedule = (void (*)(CFTypeRef,CFRunLoopRef,CFStringRef))dlsym(library,"WiFiManagerClientScheduleWithRunLoop");
    auto copy = (CFArrayRef (*)(CFTypeRef))dlsym(library,"WiFiManagerClientCopyDevices");
    auto get = (int (*)(CFTypeRef))dlsym(library,"WiFiDeviceClientGetPower");
    auto set = (void (*)(CFTypeRef,CFStringRef,CFTypeRef))dlsym(library,"WiFiManagerClientSetProperty");
    auto property = (CFTypeRef (*)(CFTypeRef,CFStringRef))dlsym(library,"WiFiManagerClientCopyProperty");
    if (!create || !schedule || !copy || !get || !set || !property) return 3;
    CFTypeRef manager = create(NULL,0);
    if (!manager) return 4;
    schedule(manager,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode); pump(.3);
    CFArrayRef devices = copy(manager);
    if (!devices || CFArrayGetCount(devices)!=1) { printJSON(@{@"error":@"wifi_device_unavailable"}); return 5; }
    CFTypeRef device = CFArrayGetValueAtIndex(devices,0);
    int initial = get(device);
    CFTypeRef allow = property(manager,CFSTR("AllowEnable"));
    bool valid = allow && CFGetTypeID(allow)==CFBooleanGetTypeID();
    bool initiallyAllowed = valid && CFBooleanGetValue((CFBooleanRef)allow);
    if (allow) CFRelease(allow);
    if ([mode isEqual:@"wifi-status"]) { printJSON(@{@"power":@(initial),@"allow_enable":valid ? @(initiallyAllowed) : NSNull.null,@"ipv4":ipv4() ?: NSNull.null}); return 0; }
    if (!initial || !valid || !initiallyAllowed) { printJSON(@{@"error":@"wifi_power_state_not_verifiable"}); return 6; }
    bool off = false, on = false;
    @try {
        set(manager,CFSTR("AllowEnable"),kCFBooleanFalse); pump(4);
        CFTypeRef state = property(manager,CFSTR("AllowEnable"));
        off = state && CFGetTypeID(state)==CFBooleanGetTypeID() && !CFBooleanGetValue((CFBooleanRef)state) && !ipv4();
        if (state) CFRelease(state);
        printJSON(@{@"power_off_confirmed":@(off),@"ipv4_when_off":ipv4() ?: NSNull.null});
    } @finally { set(manager,CFSTR("AllowEnable"),kCFBooleanTrue); }
    for (int i=0;i<50;i++) { pump(.5); if (get(device) && ipv4()) { on=true; break; } }
    pump(4);
    printJSON(@{@"power_on_confirmed":@(on),@"ipv4":ipv4() ?: NSNull.null});
    CFRelease(devices); CFRelease(manager);
    return off && on ? 0 : 7;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if (argc!=2) return 1;
        NSString *command = @(argv[1]);
        if ([command hasPrefix:@"wifi-"]) return wifi(command);
        if (getuid()!=501) { printJSON(@{@"error":@"clipboard_requires_mobile_user"}); return 8; }
        uint32_t size=0; _NSGetExecutablePath(NULL,&size); std::vector<char> buffer(size);
        if (_NSGetExecutablePath(buffer.data(),&size)) return 9;
        NSString *backup = [[@(buffer.data()) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"native-clipboard-backup.plist"];
        UIPasteboard *board = UIPasteboard.generalPasteboard;
        if ([command isEqual:@"clipboard-backup"]) {
            if ([NSFileManager.defaultManager fileExistsAtPath:backup]) return 10;
            NSError *error = nil;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:board.items format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
            if (!data || ![data writeToFile:backup options:NSDataWritingAtomic error:&error]) return 11;
            chmod(backup.fileSystemRepresentation,0600);
            printJSON(@{@"clipboard_backup_created":@YES});
        } else if ([command isEqual:@"clipboard-restore"]) {
            NSData *data = [NSData dataWithContentsOfFile:backup];
            NSArray *items = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
            if (![items isKindOfClass:NSArray.class]) return 12;
            board.items = items; pump(.3); printJSON(@{@"clipboard_restored":@([board.items isEqual:items])});
        } else if ([command isEqual:@"clipboard-set"] || [command isEqual:@"clipboard-compare"]) {
            NSData *data = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
            NSDictionary *input = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *text = input[@"text"];
            if (![text isKindOfClass:NSString.class] || text.length>256) return 13;
            if ([command isEqual:@"clipboard-set"]) { board.string=text; pump(.3); printJSON(@{@"clipboard_test_value_set":@([board.string isEqualToString:text])}); }
            else printJSON(@{@"matches":@([board.string isEqualToString:text])});
        } else return 14;
    }
    return 0;
}
