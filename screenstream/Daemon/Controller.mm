// Copyright (c) 2026 DK ViewPhone contributors. GPL-2.0-only.
#import "Controller.h"
#import "../Capture/NativeCapture.h"
#include "../Capture/FrameComparator.h"
#include "../Encoder/JPEGEncoder.h"
#include "../Streaming/LatestQueue.h"
#include "../Streaming/StreamServer.h"
#include "../Common/Clock.h"
#import <UIKit/UIKit.h>
#include <array>
#include <thread>

@interface FBSOrientationUpdate : NSObject
- (UIInterfaceOrientation)orientation;
@end
@interface FBSOrientationObserver : NSObject
- (void)setHandler:(void (^)(FBSOrientationUpdate *))handler;
- (UIInterfaceOrientation)activeInterfaceOrientation;
- (void)invalidate;
@end

@implementation DKSSController {
    dkss::Config _config;
    dkss::Metrics _metrics;
    std::unique_ptr<dkss::StreamServer> _server;
    std::shared_ptr<dkss::LatestQueue<std::shared_ptr<dkss::RawFrame>>> _queue;
    std::thread _encoder;
    std::array<std::shared_ptr<dkss::RawFrame>,3> _pool;
    std::atomic<bool> _force,_forceEncode;
    std::atomic<uint64_t> _sequence;
    DKSSNativeCapture *_capture;
    FBSOrientationObserver *_orientation;
    dispatch_source_t _captureTimer;
    BOOL _started;
    uint16_t _rotation;
}
- (instancetype)initWithConfig:(dkss::Config)config webRoot:(NSString *)webRoot {
    if((self=[super init])) {
        _config=std::move(config); _force=true; _forceEncode=true; _sequence=0;
        __weak DKSSController *weak=self;
        _server=std::make_unique<dkss::StreamServer>(_config,webRoot.UTF8String ?: "",_metrics,[weak](size_t count) {
            dispatch_async(dispatch_get_main_queue(),^{ [weak viewersChanged:count]; });
        });
    }
    return self;
}
- (BOOL)start {
    NSAssert(NSThread.isMainThread,@"controller must start on main thread");
    std::string error;
    if(!_server->start(error)) return NO;
    _started=YES; return YES;
}
- (void)updateRotation:(UIInterfaceOrientation)orientation {
    uint16_t next=orientation==UIInterfaceOrientationLandscapeLeft?90:
        orientation==UIInterfaceOrientationLandscapeRight?270:orientation==UIInterfaceOrientationPortraitUpsideDown?180:0;
    if(next!=_rotation) { _rotation=next; _force=true; }
}
- (void)viewersChanged:(size_t)count {
    if(!_started) return;
    // A queued callback can be stale after another viewer disconnects.
    count=_server->viewers();
    if(!count) { [self stopCapture]; return; }
    _force=true; _forceEncode=true;
    if(_captureTimer) return;
    _capture=[DKSSNativeCapture new];
    for(auto &frame:_pool) frame=std::make_shared<dkss::RawFrame>();
    _queue=std::make_shared<dkss::LatestQueue<std::shared_ptr<dkss::RawFrame>>>();
    auto queue=_queue;
    DKSSController *owner=self;
    _encoder=std::thread([owner,queue] {
        @autoreleasepool {
            dkss::FrameComparator comparator;
            while(auto next=queue->wait()) @autoreleasepool {
                auto frame=*next;
                if(!owner->_forceEncode.exchange(false) && comparator.identical(*frame)) { ++owner->_metrics.skipped; continue; }
                uint64_t started=dkss::nowMicros();
                auto jpeg=dkss::encodeJPEG(*frame,owner->_config.quality);
                owner->_metrics.encodeMicros.fetch_add(dkss::nowMicros()-started);
                if(jpeg.empty()) { ++owner->_metrics.encodeErrors; owner->_force=true; owner->_forceEncode=true; continue; }
                comparator.commit(*frame);
                ++owner->_metrics.encoded; owner->_metrics.outputBytes.fetch_add(jpeg.size());
                dkss::FrameInfo info{++owner->_sequence,frame->capturedMicros,frame->width,frame->height,
                    static_cast<uint32_t>(jpeg.size()),frame->orientation};
                owner->_server->publish(info,jpeg);
            }
        }
    });
    _orientation=[FBSOrientationObserver new];
    [self updateRotation:_orientation.activeInterfaceOrientation];
    __weak DKSSController *weak=self;
    [_orientation setHandler:^(FBSOrientationUpdate *update) {
        UIInterfaceOrientation orientation=update.orientation;
        dispatch_async(dispatch_get_main_queue(),^{ [weak updateRotation:orientation]; });
    }];
    _captureTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    uint64_t interval=NSEC_PER_SEC/_config.fps;
    dispatch_source_set_timer(_captureTimer,DISPATCH_TIME_NOW,interval,interval/20);
    dispatch_source_set_event_handler(_captureTimer,^{ [weak captureTick]; });
    dispatch_resume(_captureTimer);
}
- (void)captureTick {
    if(!_started || !_server->viewers()) return;
    std::shared_ptr<dkss::RawFrame> frame;
    for(auto &candidate:_pool) if(candidate.use_count()==1) { frame=candidate; break; }
    if(!frame) { ++_metrics.dropped; return; }
    uint64_t began=dkss::nowMicros(); bool force=_force.exchange(false);
    if(![_capture capture:*frame scale:_config.scale maximum:_config.maxDimension rotation:_rotation force:force]) {
        if(_capture.failed) { ++_metrics.captureErrors; _force=true; }
        else ++_metrics.skipped;
        return;
    }
    frame->capturedMicros=began; frame->captureMs=double(dkss::nowMicros()-began)/1000;
    ++_metrics.captured; _metrics.captureMicros.fetch_add(static_cast<uint64_t>(frame->captureMs*1000));
    auto result=_queue->push(frame);
    if(result==decltype(result)::replaced) ++_metrics.dropped;
}
- (void)stopCapture {
    if(_captureTimer) { dispatch_source_cancel(_captureTimer); _captureTimer=nullptr; }
    [_orientation invalidate]; _orientation=nil;
    if(_queue) _queue->close();
    if(_encoder.joinable()) _encoder.join();
    _queue.reset();
    for(auto &frame:_pool) frame.reset();
    [_capture close]; _capture=nil;
}
- (NSDictionary *)metrics {
    NSDictionary *value=@{@"type":@"metrics",@"framesCaptured":@(_metrics.captured.load()),
        @"framesEncoded":@(_metrics.encoded.load()),@"framesSkipped":@(_metrics.skipped.load()),
        @"framesDropped":@(_metrics.dropped.load()),@"encodeErrors":@(_metrics.encodeErrors.load()),
        @"captureErrors":@(_metrics.captureErrors.load()),
        @"captureFailureCode":@(_capture.failureCode),@"captureSystemStatus":@(_capture.systemStatus),
        @"captureTotalMs":@(double(_metrics.captureMicros.load())/1000),
        @"encodeTotalMs":@(double(_metrics.encodeMicros.load())/1000),
        @"outputBytes":@(_metrics.outputBytes.load()),@"socketBytes":@(_metrics.socketBytes.load()),
        @"viewers":@(_server->viewers()),@"viewOnly":@YES};
    if(_server->viewers()) {
        NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
        NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if(json) _server->publishMetrics(json.UTF8String);
    }
    return value;
}
- (void)stop {
    _started=NO; [self stopCapture];
    if(_server) _server->stop();
}
- (BOOL)healthy {
    return _server->healthy() && !(_metrics.captureErrors.load()>=5 && !_metrics.captured.load()) &&
        !(_metrics.encodeErrors.load()>=5 && !_metrics.encoded.load() && _server->viewers());
}
- (void)dealloc { [self stop]; }
@end
