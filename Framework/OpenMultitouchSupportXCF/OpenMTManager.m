//
//  OpenMTManager.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>

#import "OpenMTManagerInternal.h"
#import "OpenMTListenerInternal.h"
#import "OpenMTTouchInternal.h"
#import "OpenMTEventInternal.h"
#import "OpenMTInternal.h"

@implementation OpenMTDeviceInfo

- (instancetype)initWithDeviceRef:(MTDeviceRef)deviceRef {
    if (self = [super init]) {
        // Get device ID
        uint64_t deviceID;
        OSStatus err = MTDeviceGetDeviceID(deviceRef, &deviceID);
        if (!err) {
            _deviceID = [NSString stringWithFormat:@"%llu", deviceID];
        } else {
            _deviceID = @"Unknown";
        }
        // Determine if built-in
        _isBuiltIn = MTDeviceIsBuiltIn ? MTDeviceIsBuiltIn(deviceRef) : YES;
        // Get family ID for precise device identification
        int familyID = 0;
        MTDeviceGetFamilyID(deviceRef, &familyID);
        // Determine device name based on family ID mapping
        // Reference: https://github.com/JitouchApp/Jitouch-project/blob/3b5018e4bc839426a6ce0917cea6df753d19da10/Application/Gesture.m#L2930
        // Normally chaining this many if statements is trolling, but I'm keeping it for documentation purposes
        if (familyID == 98 || familyID == 99 || familyID == 100) {
            // Built-in trackpad (older models)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 101) {
            // Retina MacBook Pro trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 102) {
            // Retina MacBook with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 103) {
            // Retina MacBook Pro 13" with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 104) {
            // MacBook trackpad variant
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 105) {
            // MacBook with Touch Bar
            _deviceName = @"Touch Bar";
        } else if (familyID == 109) {
            // M4 Macbook Pro Trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 112 || familyID == 113) {
            // Magic Mouse & Magic Mouse 2/3
            _deviceName = @"Magic Mouse";
        } else if (familyID == 128 || familyID == 129 || familyID == 130) {
            // Magic Trackpad, Magic Trackpad 2, Magic Trackpad 3
            _deviceName = @"Magic Trackpad";
        } else {
            // Unknown device - use dimensions to make an educated guess
            int width = 0, height = 0;
            MTDeviceGetSensorSurfaceDimensions(deviceRef, &width, &height);
            // Heuristic: trackpads are typically wider than tall and have reasonable dimensions
            // Touch Bar is very wide and narrow (>1000 width, <100 height)
            // Regular trackpads are usually wider than tall but not extremely so
            if (width > 1000 && height < 100) {
                _deviceName = [NSString stringWithFormat:@"Unknown Touch Bar (FamilyID: %d)", familyID];
            } else if (width > height && width > 50 && height > 20) {
                // Likely a trackpad: wider than tall, reasonable dimensions
                _deviceName = [NSString stringWithFormat:@"Unknown Trackpad (FamilyID: %d)", familyID];
            } else {
                // Probably not a trackpad
                _deviceName = [NSString stringWithFormat:@"Unknown Device (FamilyID: %d)", familyID];
            }
        }
    }
    return self;
}

@end

@interface OpenMTManager()

@property (strong, readwrite) NSMutableArray *listeners;
@property (strong, readwrite) NSArray<OpenMTDeviceInfo *> *availableDeviceInfos;
@property (strong, readwrite) NSArray<OpenMTDeviceInfo *> *activeDeviceInfos;
@property (strong, readwrite) NSMutableDictionary<NSString *, NSValue *> *deviceRefs;
@property (strong, readwrite) NSMutableDictionary<NSValue *, NSString *> *deviceIDsByRef;
@property (copy, readwrite) NSString *primaryDeviceID;

- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices;
@end

@implementation OpenMTManager

+ (BOOL)systemSupportsMultitouch {
    return MTDeviceIsAvailable();
}

+ (OpenMTManager *)sharedManager {
    static OpenMTManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = self.new;
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        self.listeners = NSMutableArray.new;
        self.deviceRefs = NSMutableDictionary.new;
        self.deviceIDsByRef = NSMutableDictionary.new;
        [self enumerateDevices];
        
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(didWakeUp:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}


- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices {
    NSMutableArray<OpenMTDeviceInfo *> *devices = [NSMutableArray array];
    
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:deviceRef];
                [devices addObject:deviceInfo];
            }
            CFRelease(deviceList);
        }
    }
    
    if (devices.count == 0 && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:defaultDevice];
            [devices addObject:deviceInfo];
            // Don't release defaultDevice here since we store the reference elsewhere
        }
    }
    
    return [devices copy];
}

- (void)enumerateDevices {
    NSArray<OpenMTDeviceInfo *> *devices = [self collectAvailableDevices];
    self.availableDeviceInfos = devices;
    if (devices.count > 0) {
        OpenMTDeviceInfo *defaultDevice = devices[0];
        self.activeDeviceInfos = @[defaultDevice];
        self.primaryDeviceID = defaultDevice.deviceID;
    } else {
        self.activeDeviceInfos = @[];
        self.primaryDeviceID = nil;
    }
}

- (MTDeviceRef)createDeviceRefForDeviceID:(NSString *)deviceID {
    if (!deviceID.length) {
        return NULL;
    }
    MTDeviceRef foundDevice = NULL;
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                uint64_t rawID = 0;
                OSStatus err = MTDeviceGetDeviceID(deviceRef, &rawID);
                if (!err) {
                    NSString *devID = [NSString stringWithFormat:@"%llu", rawID];
                    if ([devID isEqualToString:deviceID]) {
                        foundDevice = deviceRef;
                        CFRetain(foundDevice);
                        break;
                    }
                }
            }
            CFRelease(deviceList);
        }
    }
    if (!foundDevice && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            uint64_t rawID = 0;
            OSStatus err = MTDeviceGetDeviceID(defaultDevice, &rawID);
            if (!err) {
                NSString *devID = [NSString stringWithFormat:@"%llu", rawID];
                if ([devID isEqualToString:deviceID]) {
                    foundDevice = defaultDevice;
                } else {
                    MTDeviceRelease(defaultDevice);
                }
            } else {
                MTDeviceRelease(defaultDevice);
            }
        }
    }
    return foundDevice;
}

- (void)storeDeviceRef:(MTDeviceRef)deviceRef deviceID:(NSString *)deviceID {
    if (!deviceRef || !deviceID.length) {
        return;
    }
    NSValue *refValue = [NSValue valueWithPointer:deviceRef];
    self.deviceRefs[deviceID] = refValue;
    self.deviceIDsByRef[refValue] = deviceID;
}

- (void)clearDeviceRefs {
    for (NSValue *refValue in self.deviceRefs.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef) {
            MTDeviceRelease(deviceRef);
        }
    }
    [self.deviceRefs removeAllObjects];
    [self.deviceIDsByRef removeAllObjects];
}

- (BOOL)refreshActiveDeviceRefs {
    [self clearDeviceRefs];
    BOOL didAddAny = NO;
    for (OpenMTDeviceInfo *deviceInfo in self.activeDeviceInfos) {
        MTDeviceRef deviceRef = [self createDeviceRefForDeviceID:deviceInfo.deviceID];
        if (deviceRef) {
            [self storeDeviceRef:deviceRef deviceID:deviceInfo.deviceID];
            didAddAny = YES;
        }
    }
    return didAddAny;
}

- (MTDeviceRef)primaryDeviceRef {
    if (!self.primaryDeviceID.length) {
        return NULL;
    }
    NSValue *refValue = self.deviceRefs[self.primaryDeviceID];
    if (!refValue) {
        MTDeviceRef deviceRef = [self createDeviceRefForDeviceID:self.primaryDeviceID];
        if (deviceRef) {
            [self storeDeviceRef:deviceRef deviceID:self.primaryDeviceID];
            return deviceRef;
        }
        return NULL;
    }
    return (MTDeviceRef)refValue.pointerValue;
}

- (NSString *)deviceIDForDeviceRef:(MTDeviceRef)deviceRef {
    if (!deviceRef) {
        return nil;
    }
    NSValue *refValue = [NSValue valueWithPointer:deviceRef];
    NSString *deviceID = self.deviceIDsByRef[refValue];
    if (deviceID.length) {
        return deviceID;
    }
    uint64_t rawID = 0;
    OSStatus err = MTDeviceGetDeviceID(deviceRef, &rawID);
    if (!err) {
        return [NSString stringWithFormat:@"%llu", rawID];
    }
    return nil;
}

//- (void)handlePathEvent:(OpenMTTouch *)touch {
//    NSLog(@"%@", touch.description);
//}

- (void)handleMultitouchEvent:(OpenMTEvent *)event {
    for (int i = 0; i < (int)self.listeners.count; i++) {
        OpenMTListener *listener = self.listeners[i];
        if (listener.dead) {
            [self removeListener:listener];
            continue;
        }
        if (!listener.listening) {
            continue;
        }
        dispatchResponse(^{
            [listener listenToEvent:event];
        });
    }
}

- (void)startHandlingMultitouchEvents {
    if (![self refreshActiveDeviceRefs]) {
        return;
    }
    @try {
        for (NSValue *refValue in self.deviceRefs.allValues) {
            MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
            if (!deviceRef) {
                continue;
            }
            MTRegisterContactFrameCallback(deviceRef, contactEventHandler); // work
            // MTEasyInstallPrintCallbacks(deviceRef, YES, NO, NO, NO, NO, NO); // work
            // MTRegisterPathCallback(deviceRef, pathEventHandler); // work
            // MTRegisterMultitouchImageCallback(deviceRef, MTImagePrintCallback); // not work
            MTDeviceStart(deviceRef, 0);
        }
    } @catch (NSException *exception) {
        NSLog(@"Failed Start Handling Multitouch Events");
    }
}

- (void)stopHandlingMultitouchEvents {
    @try {
        for (NSValue *refValue in self.deviceRefs.allValues) {
            MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
            if (!deviceRef || !MTDeviceIsRunning(deviceRef)) {
                continue;
            }
            MTUnregisterContactFrameCallback(deviceRef, contactEventHandler); // work
            // MTUnregisterPathCallback(deviceRef, pathEventHandler); // work
            // MTUnregisterImageCallback(deviceRef, MTImagePrintCallback); // not work
            MTDeviceStop(deviceRef);
        }
        [self clearDeviceRefs];
    } @catch (NSException *exception) {
        NSLog(@"Failed Stop Handling Multitouch Events");
    }
}

- (void)willSleep:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopHandlingMultitouchEvents];
    });
}

- (void)didWakeUp:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startHandlingMultitouchEvents];
    });
}

// Public Functions
- (void)refreshAvailableDevices {
    self.availableDeviceInfos = [self collectAvailableDevices];
}

- (NSArray<OpenMTDeviceInfo *> *)availableDevices {
    return self.availableDeviceInfos;
}

- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos {
    if (deviceInfos.count == 0) {
        return NO;
    }
    for (OpenMTDeviceInfo *deviceInfo in deviceInfos) {
        if (![self.availableDeviceInfos containsObject:deviceInfo]) {
            return NO;
        }
    }
    BOOL wasRunning = NO;
    for (NSValue *refValue in self.deviceRefs.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef && MTDeviceIsRunning(deviceRef)) {
            wasRunning = YES;
            break;
        }
    }
    if (wasRunning) {
        [self stopHandlingMultitouchEvents];
    }
    self.activeDeviceInfos = [deviceInfos copy];
    self.primaryDeviceID = deviceInfos.firstObject.deviceID;
    if (wasRunning) {
        [self startHandlingMultitouchEvents];
    }
    return YES;
}

- (NSArray<OpenMTDeviceInfo *> *)activeDevices {
    return self.activeDeviceInfos;
}

- (OpenMTListener *)addListenerWithTarget:(id)target selector:(SEL)selector {
    __block OpenMTListener *listener = nil;
    dispatchSync(dispatch_get_main_queue(), ^{
        if (!self.class.systemSupportsMultitouch) { return; }
        listener = [[OpenMTListener alloc] initWithTarget:target selector:selector];
        if (self.listeners.count == 0) {
            [self startHandlingMultitouchEvents];
        }
        [self.listeners addObject:listener];
    });
    return listener;
}

- (void)removeListener:(OpenMTListener *)listener {
    dispatchSync(dispatch_get_main_queue(), ^{
        [self.listeners removeObject:listener];
        if (self.listeners.count == 0) {
            [self stopHandlingMultitouchEvents];
        }
    });
}

- (BOOL)isHapticEnabled {
    MTDeviceRef deviceRef = [self primaryDeviceRef];
    if (!deviceRef) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(deviceRef);
    if (!actuator) {
        return NO;
    }
    
    return MTActuatorGetSystemActuationsEnabled(actuator);
}

- (BOOL)setHapticEnabled:(BOOL)enabled {
    MTDeviceRef deviceRef = [self primaryDeviceRef];
    if (!deviceRef) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(deviceRef);
    if (!actuator) {
        return NO;
    }
    
    OSStatus result = MTActuatorSetSystemActuationsEnabled(actuator, enabled);
    return result == noErr;
}

- (UInt64)findBuiltInTrackpadDeviceID {
    // Use IOKit to find the built-in trackpad (HapticKey approach)
    io_iterator_t iterator = IO_OBJECT_NULL;
    const CFMutableDictionaryRef matchingRef = IOServiceMatching("AppleMultitouchDevice");
    const kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingRef, &iterator);
    
    if (result != KERN_SUCCESS) {
        NSLog(@"❌ Failed to get matching services: 0x%x", result);
        return 0;
    }
    
    UInt64 foundDeviceID = 0;
    io_service_t service = IO_OBJECT_NULL;
    
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFMutableDictionaryRef propertiesRef = NULL;
        const kern_return_t propResult = IORegistryEntryCreateCFProperties(service, &propertiesRef, CFAllocatorGetDefault(), 0);
        
        if (propResult != KERN_SUCCESS) {
            IOObjectRelease(service);
            continue;
        }
        
        NSDictionary *properties = (__bridge_transfer NSDictionary *)propertiesRef;
        NSLog(@"🔍 Found multitouch device: %@", properties[@"Product"]);
        
        // Look for actuation-supported, built-in device (trackpad)
        NSNumber *actuationSupported = properties[@"ActuationSupported"];
        NSNumber *mtBuiltIn = properties[@"MT Built-In"];
        
        if (actuationSupported.boolValue && mtBuiltIn.boolValue) {
            NSNumber *multitouchID = properties[@"Multitouch ID"];
            foundDeviceID = multitouchID.unsignedLongLongValue;
            NSLog(@"✅ Found built-in trackpad: %@ (ID: 0x%llx)", properties[@"Product"], foundDeviceID);
            IOObjectRelease(service);
            break;
        } else {
            NSLog(@"⏭️ Skipping device %@ (ActuationSupported: %@, Built-In: %@)", 
                  properties[@"Product"], actuationSupported, mtBuiltIn);
        }
        
        IOObjectRelease(service);
    }
    
    IOObjectRelease(iterator);
    return foundDeviceID;
}
// actuation IDs range from 1-6 going weakest to strongest
// unknown 2 controls the sharpness. Test: activation id 1 with unknown2=10
// unknown 3 is used as onset/offset in other cases. onset=0 offset=2. Can be negative
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 {
    NSLog(@"🔧 Raw haptic trigger - ID: %d, unknown1: %u, unknown2: %f, unknown3: %f", actuationID, unknown1, unknown2, unknown3);
    
    // Find the built-in trackpad device using IOKit (HapticKey approach)
    UInt64 multitouchDeviceID = [self findBuiltInTrackpadDeviceID];
    if (multitouchDeviceID == 0) {
        NSLog(@"❌ Failed to find built-in trackpad device");
        return NO;
    }
    
    // Create actuator from device ID (HapticKey approach)
    CFTypeRef actuatorRef = MTActuatorCreateFromDeviceID(multitouchDeviceID);
    if (!actuatorRef) {
        NSLog(@"❌ Failed to create MTActuator from device ID");
        return NO;
    }
    
    // Open the actuator (HapticKey approach)
    IOReturn openResult = MTActuatorOpen(actuatorRef);
    if (openResult != kIOReturnSuccess) {
        NSLog(@"❌ Failed to open MTActuator: 0x%x", openResult);
        CFRelease(actuatorRef);
        return NO;
    }
    
    // Single actuate call with raw parameters
    NSLog(@"🎯 Actuating with raw parameters");
    IOReturn result = MTActuatorActuate(actuatorRef, actuationID, unknown1, unknown2, unknown3);
    NSLog(@"🎯 Actuate result: 0x%x (0 = success)", result);
    
    // Close and release
    MTActuatorClose(actuatorRef);
    CFRelease(actuatorRef);
    
    BOOL success = (result == kIOReturnSuccess);
    NSLog(@"🎯 Raw haptic result: %s", success ? "SUCCESS" : "FAILED");
    return success;
}
// Utility Tools C Language
static void dispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (!strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))) {
        block();
        return;
    }
    dispatch_sync(queue, block);
}

static void dispatchResponse(dispatch_block_t block) {
    static dispatch_queue_t responseQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        responseQueue = dispatch_queue_create("com.kyome.openmt", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_sync(responseQueue, block);
}

static void contactEventHandler(MTDeviceRef eventDevice, MTTouch eventTouches[], int numTouches, double timestamp, int frame) {
    NSMutableArray *touches = [NSMutableArray array];
    
    for (int i = 0; i < numTouches; i++) {
        OpenMTTouch *touch = [[OpenMTTouch alloc] initWithMTTouch:&eventTouches[i]];
        [touches addObject:touch];
    }
    
    OpenMTEvent *event = OpenMTEvent.new;
    event.touches = touches;
    event.deviceID = [OpenMTManager.sharedManager deviceIDForDeviceRef:eventDevice] ?: @"Unknown";
    event.frameID = frame;
    event.timestamp = timestamp;
    
    [OpenMTManager.sharedManager handleMultitouchEvent:event];
}

@end
