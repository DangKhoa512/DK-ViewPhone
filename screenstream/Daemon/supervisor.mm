// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
// Separate ScreenStream lifecycle; never reads/writes ViewPhone preferences.
#import "../Common/Preferences.h"
#import "../Common/Log.h"
#include "../Common/RecoveryPolicy.h"
#include "../Common/Clock.h"
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <notify.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char **environ;
static volatile sig_atomic_t stopping=0;
static void stopSignal(int) { stopping=1; }
static void stopChild(pid_t &child,int &channel) {
    if(child>0) {
        kill(child,SIGCONT); kill(child,SIGTERM);
        double deadline=dkss::nowSeconds()+8; int status=0; pid_t result;
        do { result=waitpid(child,&status,WNOHANG); if(result==0) usleep(100000); }
        while((result==0 || (result<0&&errno==EINTR)) && dkss::nowSeconds()<deadline);
        if(result==0) { kill(child,SIGKILL); while(waitpid(child,&status,0)<0&&errno==EINTR) {} }
    }
    child=0; if(channel>=0) close(channel); channel=-1;
}
static bool startChild(NSString *executable,const std::string &address,pid_t &child,int &channel) {
    int sockets[2]; if(socketpair(AF_UNIX,SOCK_DGRAM,0,sockets)) return false;
    for(int fd:sockets) { fcntl(fd,F_SETFD,FD_CLOEXEC); fcntl(fd,F_SETFL,O_NONBLOCK); }
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions,sockets[1],198);
    posix_spawn_file_actions_addclose(&actions,sockets[0]); posix_spawn_file_actions_addclose(&actions,sockets[1]);
    std::vector<std::string> storage;
    for(char **item=environ;*item;++item) if(strncmp(*item,"DKSS_",5)) storage.emplace_back(*item);
    storage.emplace_back("DKSS_HEARTBEAT_FD=198"); storage.emplace_back("DKSS_BIND="+address);
    std::vector<char *> env; for(auto &item:storage) env.push_back(item.data()); env.push_back(nullptr);
    char *arguments[]={const_cast<char *>(executable.fileSystemRepresentation),nullptr};
    int rc=posix_spawn(&child,executable.fileSystemRepresentation,&actions,nullptr,arguments,env.data());
    posix_spawn_file_actions_destroy(&actions); close(sockets[1]);
    if(rc) { close(sockets[0]); child=0; return false; }
    channel=sockets[0]; return true;
}
int main() {
    @autoreleasepool {
        if(getuid()!=501 || !DKSSPrepareLogDirectory()) return 1;
        NSString *lockfile=[DKSSStatePath().stringByDeletingLastPathComponent stringByAppendingPathComponent:@"supervisor.lock"];
        int lock=open(lockfile.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
        if(lock<0 || flock(lock,LOCK_EX|LOCK_NB)) return 1;
        signal(SIGTERM,stopSignal); signal(SIGINT,stopSignal); signal(SIGPIPE,SIG_IGN);
        uint32_t size=0; _NSGetExecutablePath(nullptr,&size); std::vector<char> path(size);
        if(_NSGetExecutablePath(path.data(),&size)) return 1;
        NSString *executable=[[[NSString stringWithUTF8String:path.data()] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"dkss-server"];
        NSDictionary *saved=[NSDictionary dictionary];
        NSData *stateData=[NSData dataWithContentsOfFile:DKSSStatePath()];
        if(stateData) {
            id parsed=[NSJSONSerialization JSONObjectWithData:stateData options:0 error:nil];
            BOOL valid=[parsed isKindOfClass:NSDictionary.class];
            if(valid) for(NSString *key in @[@"failures",@"windowStart",@"retryAt",@"restarts",@"latched",@"active"])
                if(![parsed[key] isKindOfClass:NSNumber.class]) { valid=NO; break; }
            if(valid) saved=parsed;
        }
        dkviewphone::RecoveryBudget budget;
        budget.failures=std::min(100u,[saved[@"failures"] unsignedIntValue]);
        budget.windowStart=[saved[@"windowStart"] doubleValue]; budget.retryAt=[saved[@"retryAt"] doubleValue];
        budget.restarts=[saved[@"restarts"] unsignedLongLongValue]; budget.latched=[saved[@"latched"] boolValue];
        if(stateData && !saved.count) budget.latched=true;
        if([saved[@"active"] boolValue]) budget.fail(NSDate.date.timeIntervalSince1970);
        double retry=dkss::nowSeconds()+std::clamp(budget.retryAt-NSDate.date.timeIntervalSince1970,0.0,60.0);
        pid_t child=0; int channel=-1;
        NSDictionary *values=DKSSReadPreferences(),*activePreferences=nil;
        std::string candidate,effective;
        double lastPreferences=0,changedAt=0,lastHeartbeat=0;
        int notification=-1; notify_register_check(DKSS_NOTIFY,&notification);
        auto persist=[&] {
            NSDictionary *state=@{@"failures":@(budget.failures),@"windowStart":@(budget.windowStart),
                @"retryAt":@(budget.retryAt),@"restarts":@(budget.restarts),@"latched":@(budget.latched),@"active":@(child>0)};
            NSData *data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
            [data writeToFile:DKSSStatePath() options:NSDataWritingAtomic error:nil];
            chmod(DKSSStatePath().fileSystemRepresentation,0600);
        };
        auto failure=[&](NSString *reason) {
            double delay=budget.fail(NSDate.date.timeIntervalSince1970);
            retry=dkss::nowSeconds()+std::max(0.0,delay);
            DKSSLog(@"recovery",@{@"reason":reason,@"failures":@(budget.failures),@"latched":@(budget.latched),@"delaySeconds":@(delay)});
            persist();
        };
        DKSSLog(@"supervisor_started",@{@"latched":@(budget.latched)});
        persist();
        while(!stopping) @autoreleasepool {
            double now=dkss::nowSeconds(); int changed=0;
            if(notification>=0) notify_check(notification,&changed);
            if(changed || now-lastPreferences>=5) { values=DKSSReadPreferences(); lastPreferences=now; }
            if(!DKSSEnabled(values)) {
                bool dirty=false;
                if(child) { stopChild(child,channel); DKSSLog(@"disabled",@{}); dirty=true; }
                if(budget.latched || budget.failures) { budget.manualOff(); retry=0; dirty=true; }
                if(dirty) persist();
                usleep(500000); continue;
            }
            auto config=DKSSConfig(values);
            if(!dkss::validToken(config.token)) {
                if(child) { stopChild(child,channel); persist(); DKSSLog(@"token_not_configured",@{}); }
                usleep(500000); continue;
            }
            if(candidate!=config.address) { candidate=config.address; changedAt=now; }
            if(child && (effective!=candidate || ![activePreferences isEqual:values])) {
                stopChild(child,channel); persist(); DKSSLog(@"configuration_reload",@{});
            }
            if(child) {
                int status=0; pid_t exited=waitpid(child,&status,WNOHANG);
                if(exited==child) { child=0; close(channel); channel=-1; failure(@"worker_exit"); }
                else {
                    char buffer[8192]; ssize_t received;
                    while((received=recv(channel,buffer,sizeof(buffer),MSG_DONTWAIT))>0) {
                        id packet=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:static_cast<NSUInteger>(received)] options:0 error:nil];
                        if(![packet isKindOfClass:NSDictionary.class] || [packet[@"pid"] intValue]!=child) continue;
                        lastHeartbeat=now;
                        if([packet[@"event"] isEqual:@"metrics"]) {
                            NSMutableDictionary *safe=[NSMutableDictionary dictionary];
                            for(NSString *key in @[@"framesCaptured",@"framesEncoded",@"framesSkipped",@"framesDropped",@"encodeErrors",@"captureErrors",
                                @"captureTotalMs",@"encodeTotalMs",@"outputBytes",@"socketBytes",@"viewers",@"cpuTotalSeconds",@"rssBytes"])
                                if([packet[key] isKindOfClass:NSNumber.class]) safe[key]=packet[key];
                            DKSSLog(@"metrics",safe);
                        }
                    }
                    if(now-lastHeartbeat>15) { stopChild(child,channel); failure(@"heartbeat_timeout"); }
                }
            }
            if(!child && !budget.latched && now>=retry && now-changedAt>=3 && DKSSEnabled(DKSSReadPreferences())) {
                if(startChild(executable,candidate,child,channel)) {
                    ++budget.restarts; lastHeartbeat=now; effective=candidate; activePreferences=values; persist();
                    DKSSLog(@"worker_started",@{@"pid":@(child),@"starts":@(budget.restarts)});
                } else failure(@"spawn_failed");
            }
            usleep(500000);
        }
        stopChild(child,channel); persist(); if(notification>=0) notify_cancel(notification); close(lock);
        DKSSLog(@"supervisor_stopped",@{}); return 0;
    }
}
