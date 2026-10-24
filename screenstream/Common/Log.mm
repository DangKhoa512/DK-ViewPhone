// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#import "Log.h"
#include <fcntl.h>
#include <cerrno>
#include <sys/stat.h>
#include <unistd.h>

static NSString *directory=@"/var/mobile/Library/Logs/DKScreenStream";
BOOL DKSSPrepareLogDirectory(void) {
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    struct stat info{};
    return lstat(directory.fileSystemRepresentation,&info)==0 && S_ISDIR(info.st_mode) && info.st_uid==getuid() &&
        chmod(directory.fileSystemRepresentation,0700)==0;
}
NSString *DKSSStatePath(void) { return [directory stringByAppendingPathComponent:@"recovery.json"]; }
void DKSSLog(NSString *event,NSDictionary *fields) {
    NSMutableDictionary *record=[fields mutableCopy] ?: [NSMutableDictionary dictionary];
    record[@"event"]=event; record[@"time_unix"]=@(NSDate.date.timeIntervalSince1970);
    record[@"version"]=@"0.1.0";
    NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if(!data.length || data.length>8192) return;
    NSString *filename=[directory stringByAppendingPathComponent:@"diagnostic.jsonl"];
    struct stat info{};
    if(lstat(filename.fileSystemRepresentation,&info)==0 && (!S_ISREG(info.st_mode)||info.st_uid!=getuid())) return;
    if(info.st_size+static_cast<off_t>(data.length)+1>256*1024) {
        unlink([[directory stringByAppendingPathComponent:@"diagnostic.jsonl.3"] fileSystemRepresentation]);
        for(int n=2;n>=1;--n) rename([[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"diagnostic.jsonl.%d",n]] fileSystemRepresentation],
            [[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"diagnostic.jsonl.%d",n+1]] fileSystemRepresentation]);
        rename(filename.fileSystemRepresentation,[[directory stringByAppendingPathComponent:@"diagnostic.jsonl.1"] fileSystemRepresentation]);
    }
    int fd=open(filename.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0) return;
    NSMutableData *line=[data mutableCopy]; [line appendBytes:"\n" length:1];
    const uint8_t *bytes=static_cast<const uint8_t *>(line.bytes); size_t left=line.length;
    while(left) { ssize_t n=write(fd,bytes,left); if(n<0&&errno==EINTR) continue; if(n<=0) break; bytes+=n; left-=static_cast<size_t>(n); }
    close(fd);
}
