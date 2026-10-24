// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#import "Controller.h"
#import "../Common/Preferences.h"
#import "../Common/Log.h"
#include <signal.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <mach/mach.h>
#include <unistd.h>

extern "C" const char *jbroot(const char *);
static volatile sig_atomic_t stopping=0;
static void stopSignal(int) { stopping=1; }
int main() {
    @autoreleasepool {
        if(getuid()!=501) return 1;
        signal(SIGTERM,stopSignal); signal(SIGINT,stopSignal); signal(SIGPIPE,SIG_IGN);
        NSDictionary *preferences=DKSSReadPreferences();
        if(!DKSSEnabled(preferences)) return 0;
        dkss::Config config=DKSSConfig(preferences);
        const char *address=getenv("DKSS_BIND");
        if(address) config.address=address;
        const char *root=jbroot("/usr/share/dk-screenstream/web");
        if(!root || !dkss::validToken(config.token)) return 1;
        DKSSController *controller=[[DKSSController alloc] initWithConfig:config webRoot:[NSString stringWithUTF8String:root]];
        if(![controller start]) return 1;
        const char *channel=getenv("DKSS_HEARTBEAT_FD");
        int fd=channel?atoi(channel):-1;
        if(fd!=198) fd=-1;
        if(fd>=0) { int yes=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes)); }
        __block unsigned ticks=0;
        __block int result=0;
        dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,2*NSEC_PER_SEC,NSEC_PER_MSEC*50);
        dispatch_source_set_event_handler(timer,^{
            @autoreleasepool {
                BOOL finishing=stopping || (fd>=0 && getppid()==1) || !controller.healthy;
                NSMutableDictionary *packet=[@{@"event":@"heartbeat",@"pid":@(getpid())} mutableCopy];
                NSDictionary *metrics=[controller metrics];
                if(++ticks%15==0 || finishing) {
                    [packet addEntriesFromDictionary:metrics]; packet[@"event"]=@"metrics";
                    struct rusage usage{}; getrusage(RUSAGE_SELF,&usage);
                    packet[@"cpuTotalSeconds"]=@(usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+
                        usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6);
                    mach_task_basic_info_data_t memory{}; mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;
                    if(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,reinterpret_cast<task_info_t>(&memory),&count)==KERN_SUCCESS)
                        packet[@"rssBytes"]=@(memory.resident_size);
                }
                NSData *data=[NSJSONSerialization dataWithJSONObject:packet options:0 error:nil];
                if(fd>=0 && data.length) (void)send(fd,data.bytes,data.length,MSG_DONTWAIT);
                if(finishing) { result=stopping?0:1; CFRunLoopStop(CFRunLoopGetMain()); }
            }
        });
        dispatch_resume(timer); CFRunLoopRun(); dispatch_source_cancel(timer);
        [controller stop]; if(fd>=0) close(fd); return result;
    }
}
