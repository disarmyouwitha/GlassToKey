//
//  OpenMTListener.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import "OpenMTListenerInternal.h"

@implementation OpenMTListener {
@private
    OpenMTEventCallback _callback;
    OpenMTRawFrameCallback _rawCallback;
    __weak id _target;
    SEL _selector;
}

- (instancetype)init {
    if (self = [super init]) {
        _listening = YES;
    }
    return self;
}

- (instancetype)initWithTarget:(id)target selector:(SEL)selector {
    if (self = [self init]) {
        _target = target;
        _selector = selector;
    }
    return self;
}

- (instancetype)initWithRawCallback:(OpenMTRawFrameCallback)callback {
    if (self = [self init]) {
        _rawCallback = [callback copy];
    }
    return self;
}

- (void)listenToEvent:(OpenMTEvent *)event {
    if (self.dead || !self.listening) {
        return;
    }
    if (_callback) {
        _callback(event);
        return;
    }
    if (_target) {
        ((void(*)(id, SEL, OpenMTEvent*))[_target methodForSelector:_selector])(_target, _selector, event);
        return;
    }
}

- (void)listenToRawFrameWithTouches:(const MTTouch *)touches
                              count:(int)numTouches
                          timestamp:(double)timestamp
                              frame:(int)frame
                           deviceID:(uint64_t)deviceID {
    if (self.dead || !self.listening || !_rawCallback) {
        return;
    }
    _rawCallback(touches, numTouches, timestamp, frame, deviceID);
}

- (BOOL)dead {
    return !(_callback
             || _rawCallback
             || (_target && _selector && [_target respondsToSelector:_selector]));
}

@end
