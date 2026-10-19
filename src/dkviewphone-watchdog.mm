// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
// Supervises the existing engine; does not capture, authenticate or inject input.
#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <mach-o/dyld.h>
#import <net/if.h>
#import <poll.h>
#import <signal.h>
#import <spawn.h>
#import <sys/file.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <time.h>
#import <vector>
#import <string>
#import "DKRecoveryPolicy.h"
#import "DKViewPhonePolicy.h"
#import "DKNetworkAddress.h"

extern char **environ;
static NSString *directory = @"/var/mobile/Library/Logs/DKViewPhone";
static volatile sig_atomic_t stopping = 0;
static void stopSignal(int) { stopping = 1; }
static double monotonicTime() { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9; }
static double wallTime() { return NSDate.date.timeIntervalSince1970; }
static NSString *path(NSString *name) { return [directory stringByAppendingPathComponent:name]; }

static bool safeDirectory() {
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:&error]) return false;
    struct stat st = {};
    if (lstat(directory.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) return false;
    return chmod(directory.fileSystemRepresentation, 0700) == 0;
}

static void logEvent(NSString *event, NSDictionary *fields) {
    // Callers provide fixed schemas, never format strings, prefs or protocol payloads.
    NSMutableDictionary *record = [fields mutableCopy] ?: [NSMutableDictionary dictionary];
    record[@"event"] = event; record[@"time_unix"] = @(wallTime()); record[@"version"] = @PACKAGE_VERSION;
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    if (!data.length || data.length > 4095) return;
    NSString *file = path(@"diagnostic.jsonl");
    struct stat st = {};
    if (!lstat(file.fileSystemRepresentation, &st) && (!S_ISREG(st.st_mode) || st.st_uid != getuid())) return;
    if (st.st_size + (off_t)data.length + 1 > 256 * 1024) {
        unlink(path(@"diagnostic.jsonl.3").fileSystemRepresentation);
        for (int i = 2; i >= 1; --i)
            rename(path([NSString stringWithFormat:@"diagnostic.jsonl.%d", i]).fileSystemRepresentation,
                path([NSString stringWithFormat:@"diagnostic.jsonl.%d", i + 1]).fileSystemRepresentation);
        rename(file.fileSystemRepresentation, path(@"diagnostic.jsonl.1").fileSystemRepresentation);
    }
    int fd = open(file.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return;
    NSMutableData *line = [data mutableCopy]; [line appendBytes:"\n" length:1];
    const uint8_t *bytes = (const uint8_t *)line.bytes; size_t left = line.length;
    while (left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        left -= n; bytes += n;
    }
    close(fd);
}

static NSDictionary *preferences() {
    CFStringRef domain = CFSTR("com.82flex.trollvnc");
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFDictionaryRef values = CFPreferencesCopyMultiple(NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(values) ?: @{};
}

static NSDictionary<NSString *, NSString *> *interfaces() {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses)) return result;
    for (auto *a = addresses; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET || !(a->ifa_flags & IFF_UP)) continue;
        auto *address = (struct sockaddr_in *)a->ifa_addr;
        if (!dkviewphone::privateIPv4(ntohl(address->sin_addr.s_addr))) continue;
        char buffer[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer)))
            result[@(a->ifa_name)] = @(buffer);
    }
    freeifaddrs(addresses);
    return result;
}

static void stopChild(pid_t &pid, int &channel) {
    if (pid > 0) {
        kill(pid, SIGCONT); kill(pid, SIGTERM);
        double deadline = monotonicTime() + 3;
        int status = 0;
        while (waitpid(pid, &status, WNOHANG) == 0 && monotonicTime() < deadline) usleep(100000);
        // This PID is an unreaped child of this process; cannot refer to a reused PID.
        if (waitpid(pid, &status, WNOHANG) == 0) { kill(pid, SIGKILL); while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {} }
    }
    pid = 0;
    if (channel >= 0) close(channel);
    channel = -1;
}

static bool startChild(NSString *executable, NSString *bind, pid_t &pid, int &channel) {
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, sockets)) return false;
    for (int fd : sockets) { fcntl(fd, F_SETFD, FD_CLOEXEC); fcntl(fd, F_SETFL, O_NONBLOCK); }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, sockets[1], 198);
    posix_spawn_file_actions_addclose(&actions, sockets[0]);
    posix_spawn_file_actions_addclose(&actions, sockets[1]);
    std::vector<std::string> environment;
    for (char **e = environ; *e; ++e) {
        if (strncmp(*e, "DK_VIEWPHONE_", 13) && strncmp(*e, "TROLLVNC_PASSWORD=", 17) &&
            strncmp(*e, "TROLLVNC_VIEWONLY_PASSWORD=", 26)) environment.emplace_back(*e);
    }
    environment.emplace_back("DK_VIEWPHONE_HEARTBEAT_FD=198");
    environment.emplace_back(std::string("DK_VIEWPHONE_BIND=") + bind.UTF8String);
    std::vector<char *> env;
    for (auto &e : environment) env.push_back(e.data());
    env.push_back(NULL);
    char *argv[] = {(char *)executable.fileSystemRepresentation, (char *)"-daemon", NULL};
    int rc = posix_spawn(&pid, executable.fileSystemRepresentation, &actions, NULL, argv, env.data());
    posix_spawn_file_actions_destroy(&actions); close(sockets[1]);
    if (rc) { close(sockets[0]); pid = 0; errno = rc; return false; }
    channel = sockets[0]; return true;
}

static bool probeListener(NSString *bind, int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return false;
    fcntl(fd, F_SETFL, O_NONBLOCK);
    struct sockaddr_in addr = {}; addr.sin_len = sizeof(addr); addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, bind.UTF8String, &addr.sin_addr);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    struct pollfd p = {fd, POLLOUT, 0}; int error = 0; socklen_t size = sizeof(error);
    if (rc && (errno != EINPROGRESS || poll(&p, 1, 500) <= 0 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) || error)) {
        close(fd); return false;
    }
    char banner[12]; size_t received = 0;
    double deadline = monotonicTime() + 1;
    while (received < sizeof(banner) && monotonicTime() < deadline) {
        p.events = POLLIN;
        if (poll(&p, 1, 200) <= 0) continue;
        ssize_t n = recv(fd, banner + received, sizeof(banner) - received, 0);
        if (n <= 0) break;
        received += n;
    }
    close(fd);
    return received == sizeof(banner) && memcmp(banner, "RFB 003.", 8) == 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        bool selfTest = argc == 2 && !strcmp(argv[1], "--self-test-log");
        if (selfTest) directory = [directory stringByAppendingPathComponent:@"RotationSelfTest"];
        if (!safeDirectory()) return 1;
        if (selfTest) {
            NSString *padding = [@"x" stringByPaddingToLength:3700 withString:@"x" startingAtIndex:0];
            for (int i = 0; i < 400; ++i) @autoreleasepool { logEvent(@"rotation_self_test", @{@"index":@(i),@"padding":padding}); }
            bool valid = true; unsigned files = 0, lines = 0;
            for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
                if (![name hasPrefix:@"diagnostic.jsonl"]) { valid = false; continue; }
                NSData *data = [NSData dataWithContentsOfFile:path(name)];
                valid = valid && data.length <= 256 * 1024; ++files;
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                    if (!line.length) continue;
                    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    valid = valid && [obj isKindOfClass:NSDictionary.class]; ++lines;
                }
            }
            valid = valid && files == 4 && lines > 0;
            printf("{\"rotation_passed\":%s,\"files\":%u,\"valid_json_lines\":%u}\n", valid ? "true" : "false", files, lines);
            [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
            return valid ? 0 : 1;
        }
        if (argc == 2 && !strcmp(argv[1], "--diagnostics")) {
            for (NSString *name in @[@"diagnostic.jsonl.3", @"diagnostic.jsonl.2", @"diagnostic.jsonl.1", @"diagnostic.jsonl", @"recovery.json"]) {
                NSData *data = [NSData dataWithContentsOfFile:path(name)];
                if (data.length && data.length <= 256 * 1024) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); }
            }
            return 0;
        }
        int lock = open(path(@"supervisor.lock").fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) return 1;
        signal(SIGTERM, stopSignal); signal(SIGINT, stopSignal); signal(SIGPIPE, SIG_IGN);
        uint32_t size = 0; _NSGetExecutablePath(NULL, &size);
        std::vector<char> buffer(size);
        if (_NSGetExecutablePath(buffer.data(), &size)) return 1;
        NSString *executable = [[@(buffer.data()) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"trollvncserver"];
        dkviewphone::RecoveryBudget budget;
        NSData *stateData = [NSData dataWithContentsOfFile:path(@"recovery.json")];
        NSDictionary *saved = [NSJSONSerialization JSONObjectWithData:stateData ?: [NSData data]
            options:0 error:nil];
        bool badState = stateData && ![saved isKindOfClass:NSDictionary.class];
        if (![saved isKindOfClass:NSDictionary.class]) saved = @{};
        budget.failures = std::min(100u, [saved[@"failures"] unsignedIntValue]);
        budget.restarts = [saved[@"restarts"] unsignedLongLongValue];
        budget.windowStart = [saved[@"window_start"] doubleValue]; budget.retryAt = [saved[@"retry_at"] doubleValue];
        budget.latched = [saved[@"latched"] boolValue];
        if (badState) budget.latched = true;
        if ([saved[@"worker_active"] boolValue]) budget.fail(wallTime());
        NSString *lastReason = badState ? @"invalid_recovery_state" : [saved[@"worker_active"] boolValue] ? @"supervisor_unclean_exit" : @"startup";
        NSString *interface = saved[@"interface"];
        NSString *selectedBind = saved[@"selected_bind"];
        pid_t child = 0; int channel = -1;
        bool wasEnabled = false, everStarted = [saved[@"ever_started"] boolValue] || [saved[@"worker_active"] boolValue] || budget.restarts > 0;
        double retryDeadline = monotonicTime() + std::clamp(budget.retryAt - wallTime(), 0.0, 60.0);
        double lastBeat = 0, started = 0, lastProbe = 0, changedAt = 0;
        unsigned probeFailures = 0;
        NSString *effectiveBind = nil, *observedBind = nil;
        NSDictionary *activePrefs = nil;
        auto persist = [&]() {
            NSDictionary *state = @{@"schema":@1, @"failures":@(budget.failures), @"restarts":@(budget.restarts),
                @"window_start":@(budget.windowStart), @"retry_at":@(budget.retryAt), @"latched":@(budget.latched),
                @"worker_active":@(child > 0), @"ever_started":@(everStarted), @"last_reason":lastReason,
                @"interface":interface ?: @"", @"selected_bind":selectedBind ?: @""};
            NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
            [data writeToFile:path(@"recovery.json") options:NSDataWritingAtomic error:nil];
            chmod(path(@"recovery.json").fileSystemRepresentation, 0600);
        };
        auto failure = [&](NSString *reason, int status) {
            lastReason = reason; double delay = budget.fail(wallTime());
            retryDeadline = monotonicTime() + std::max(0.0, delay);
            logEvent(@"recovery", @{@"reason":reason, @"wait_status":@(status), @"failures":@(budget.failures),
                @"restarts":@(budget.restarts), @"delay_s":@(delay), @"latched":@(budget.latched)});
            persist();
        };
        logEvent(@"supervisor_started", @{@"latched":@(budget.latched), @"restarts":@(budget.restarts)});
        while (!stopping) {
            @autoreleasepool {
                NSDictionary *prefs = preferences();
                bool enabled = [prefs[@"Enabled"] boolValue];
                if (!enabled) {
                    if (child) { stopChild(child, channel); lastReason = @"manual_off"; logEvent(@"disabled", @{}); }
                    if (wasEnabled || budget.latched || budget.failures) { budget.manualOff(); retryDeadline = 0; persist(); }
                    wasEnabled = false;
                    usleep(500000); continue;
                }
                wasEnabled = true;
                NSString *bind = [prefs[@"BindHost"] isKindOfClass:NSString.class]
                    ? [prefs[@"BindHost"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                    : @"auto";
                if (![selectedBind isEqualToString:bind]) { selectedBind = bind; interface = nil; }
                NSString *candidate = nil;
                if (DKBindHostIsAutomatic(bind.UTF8String)) {
                    char address[INET_ADDRSTRLEN];
                    DKAutomaticLANIPv4(address);
                    candidate = [NSString stringWithUTF8String:address];
                } else {
                    NSDictionary *addresses = interfaces();
                    // A concrete address keeps its selected adapter across DHCP;
                    // auto alone may choose a different LAN adapter.
                    if (!interface.length) for (NSString *name in addresses)
                        if ([addresses[name] isEqualToString:bind]) { interface = name; break; }
                    candidate = interface.length ? addresses[interface] : nil;
                    struct in_addr numeric = {};
                    if (inet_pton(AF_INET, bind.UTF8String, &numeric) == 1 && (ntohl(numeric.s_addr) >> 24) == 127) candidate = bind;
                }
                if (![observedBind isEqualToString:candidate] && (observedBind || candidate)) {
                    observedBind = candidate; changedAt = monotonicTime();
                    logEvent(@"network_changed", @{@"available":@(candidate != nil)});
                }
                if (child && (!candidate || ![effectiveBind isEqualToString:candidate] || ![activePrefs isEqual:prefs])) {
                    lastReason = !candidate ? @"network_unavailable" : ![effectiveBind isEqualToString:candidate] ? @"network_rebind" : @"configuration_changed";
                    stopChild(child, channel); persist();
                    logEvent(@"worker_stopped", @{@"reason":lastReason});
                }
                if (!candidate || monotonicTime() - changedAt < 3) { usleep(500000); continue; }
                if (child) {
                    int status = 0; pid_t exited = waitpid(child, &status, WNOHANG);
                    if (exited == child) {
                        child = 0; close(channel); channel = -1;
                        if (WIFEXITED(status) && WEXITSTATUS(status) == 75) {
                            lastReason = @"requested_reload"; persist(); logEvent(@"worker_stopped", @{@"reason":lastReason});
                        } else failure(WIFSIGNALED(status) ? @"server_signal" : @"server_exit", status);
                    } else {
                        char bytes[4096]; ssize_t n;
                        while ((n = recv(channel, bytes, sizeof(bytes), MSG_DONTWAIT)) > 0) {
                            NSDictionary *packet = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:n] options:0 error:nil];
                            if (![packet isKindOfClass:NSDictionary.class] || [packet[@"pid"] intValue] != child) continue;
                            lastBeat = monotonicTime();
                            if ([packet[@"event"] isEqual:@"metrics"]) {
                                NSMutableDictionary *allowed = [NSMutableDictionary dictionary];
                                for (NSString *key in @[@"clients",@"interval_s",@"changed_frames",@"changed_fps",@"updates_sent",
                                    @"frame_processing_mean_ms",@"frame_processing_max_ms",@"cpu_percent",@"rss_bytes"])
                                    if ([packet[key] isKindOfClass:NSNumber.class]) allowed[key] = packet[key];
                                logEvent(@"metrics", allowed);
                            }
                        }
                        double now = monotonicTime();
                        if (now - lastBeat > 30 && now - started > 30) {
                            stopChild(child, channel); failure(@"main_runloop_unresponsive", 0);
                        } else if (now - lastProbe >= 30 && now - started > 10) {
                            lastProbe = now;
                            int port = prefs[@"Port"] ? [prefs[@"Port"] intValue] : 5901;
                            bool reverse = [prefs[@"ReverseMode"] isKindOfClass:NSString.class] && ![prefs[@"ReverseMode"] isEqual:@"none"] && ![prefs[@"ReverseMode"] isEqual:@"off"];
                            if (reverse || probeListener(effectiveBind, port)) probeFailures = 0;
                            else if (++probeFailures >= 3) { stopChild(child, channel); failure(@"listener_unresponsive", 0); }
                        }
                    }
                }
                // Read intent again immediately before spawn; a pending recovery must
                // never overwrite Enabled or re-enable a manually stopped server.
                if (!child && !budget.latched && monotonicTime() >= retryDeadline && [preferences()[@"Enabled"] boolValue]) {
                    if (startChild(executable, candidate, child, channel)) {
                        if (everStarted) ++budget.restarts;
                        everStarted = true; activePrefs = prefs; effectiveBind = candidate;
                        lastBeat = started = lastProbe = monotonicTime(); probeFailures = 0;
                        persist(); logEvent(@"worker_started", @{@"pid":@(child), @"reason":lastReason, @"restarts":@(budget.restarts)});
                    } else failure(@"spawn_failed", errno);
                }
            }
            usleep(500000);
        }
        stopChild(child, channel); lastReason = @"supervisor_stopped"; persist();
        logEvent(@"supervisor_stopped", @{}); close(lock);
    }
    return 0;
}
