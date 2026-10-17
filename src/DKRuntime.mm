// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#import "DKRuntime.h"
#import <atomic>
#import <fcntl.h>
#import <mach/mach.h>
#import <sys/resource.h>
#import <sys/socket.h>
#import <signal.h>
#import <unistd.h>
#import <time.h>

static std::atomic<uint64_t> frames(0), updates(0), frameMicros(0), maxMicros(0);
static std::atomic<int> clients(0);
static volatile sig_atomic_t terminating = 0;
static NSMutableDictionary *pendingUpdates;
void DKRequestTermination(void) { terminating = 1; }
bool DKTerminationRequested(void) { return terminating != 0; }
void DKClientDelta(int delta) { clients.fetch_add(delta); }
void DKUpdateEnd(void *client, bool success) {
    @synchronized(pendingUpdates) {
        NSValue *key = [NSValue valueWithPointer:client];
        NSArray *entry = pendingUpdates[key];
        if (entry) { close([entry[0] intValue]); [pendingUpdates removeObjectForKey:key]; }
    }
    if (success) updates.fetch_add(1);
}
void DKUpdateBegin(void *client, int socket) {
    int fd = dup(socket);
    if (fd < 0) return;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    @synchronized(pendingUpdates) {
        NSValue *key = [NSValue valueWithPointer:client];
        NSArray *old = pendingUpdates[key];
        if (old) close([old[0] intValue]);
        pendingUpdates[key] = @[@(fd), @(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9 + 10)];
    }
}
void DKFrameCompleted(double ms) {
    uint64_t value = (uint64_t)(ms * 1000);
    frames.fetch_add(1); frameMicros.fetch_add(value);
    uint64_t old = maxMicros.load();
    while (old < value && !maxMicros.compare_exchange_weak(old, value)) {}
}

void DKStartRuntime(void) {
    pendingUpdates = [NSMutableDictionary dictionary];
    const char *value = getenv("DK_VIEWPHONE_HEARTBEAT_FD");
    int fd = value ? atoi(value) : -1;
    if (fd != 198) fd = -1;
    static dispatch_source_t timer, orphanTimer;
    // Main-runloop progress, independent of capture/dirty frames and connected viewers.
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC / 5);
    dispatch_source_set_event_handler(timer, ^{
        @autoreleasepool {
            if (terminating) { CFRunLoopStop(CFRunLoopGetMain()); return; }
            if (fd < 0) return;
            static double previousTime = 0, previousCPU = 0;
            static uint64_t previousFrames = 0, previousUpdates = 0, previousMicros = 0;
            double now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
            NSMutableDictionary *packet = [@{@"event":@"heartbeat", @"pid":@(getpid()),
                @"clients":@(clients.load())} mutableCopy];
            if (!previousTime || now - previousTime >= 30) {
                struct rusage usage = {};
                getrusage(RUSAGE_SELF, &usage);
                double cpu = usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6 +
                    usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
                mach_task_basic_info_data_t memory = {};
                mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
                kern_return_t rc = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&memory, &count);
                uint64_t f = frames.load(), u = updates.load(), m = frameMicros.load();
                double elapsed = previousTime ? now - previousTime : 0;
                packet[@"event"] = @"metrics";
                packet[@"interval_s"] = @(elapsed);
                packet[@"changed_frames"] = @(f - previousFrames);
                packet[@"changed_fps"] = @(elapsed > 0 ? (f - previousFrames) / elapsed : 0);
                packet[@"updates_sent"] = @(u - previousUpdates);
                packet[@"frame_processing_mean_ms"] = @(f > previousFrames ? (m - previousMicros) / 1000.0 / (f - previousFrames) : 0);
                packet[@"frame_processing_max_ms"] = @(maxMicros.exchange(0) / 1000.0);
                packet[@"cpu_percent"] = @(elapsed > 0 ? (cpu - previousCPU) * 100 / elapsed : 0);
                packet[@"rss_bytes"] = @(rc == KERN_SUCCESS ? memory.resident_size : 0);
                previousTime = now; previousCPU = cpu;
                previousFrames = f; previousUpdates = u; previousMicros = m;
            }
            NSData *data = [NSJSONSerialization dataWithJSONObject:packet options:0 error:nil];
            if (data.length) send(fd, data.bytes, data.length, MSG_DONTWAIT);
        }
    });
    dispatch_resume(timer);
    {
        int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        // A killed supervisor must not leave an orphan engine/listener behind.
        orphanTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(orphanTimer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC / 5);
        dispatch_source_set_event_handler(orphanTimer, ^{
          @autoreleasepool {
            if (fd >= 0 && getppid() == 1) _exit(0);
            double now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
            @synchronized(pendingUpdates) {
                for (NSValue *key in pendingUpdates.allKeys) {
                    NSArray *entry = pendingUpdates[key];
                    if (now < [entry[1] doubleValue]) continue;
                    // Duplicate refers to the same socket even if its original fd
                    // was closed/reused. Shutdown wakes the engine's blocked writer.
                    int stalled = [entry[0] intValue];
                    shutdown(stalled, SHUT_RDWR); close(stalled);
                    [pendingUpdates removeObjectForKey:key];
                }
            }
          }
        });
        dispatch_resume(orphanTimer);
    }
}
