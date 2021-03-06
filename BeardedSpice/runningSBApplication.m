//
//  runningApplication.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 07.03.15.
//  Copyright (c) 2015 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "runningSBApplication.h"
#import "EHSystemUtils.h"
#import "NSString+Utils.h"

#define COMMAND_TIMEOUT         3 // 0.3 second
#define RAISING_WINDOW_DELAY    0.1 //0.1 second

@implementation runningSBApplication {
    pid_t _processIdentifier;
    NSRunningApplication *_runningApplicationForHide;
    NSCondition *_lockForHide;
}

static NSMutableDictionary *_sharedAppHandler;

+ (instancetype)sharedApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    
    if ([NSString isNullOrEmpty:bundleIdentifier]) {
        return nil;
    }
    
    @synchronized(self) {
        @autoreleasepool {
            
            if (_sharedAppHandler == nil) {
                _sharedAppHandler = [NSMutableDictionary dictionary];
            }
            runningSBApplication *app = _sharedAppHandler[bundleIdentifier];
            if (! app) {
                
                app = [[runningSBApplication alloc] initWithApplication:nil bundleIdentifier:bundleIdentifier];
                if ([app runningApplicationCreateFromBundleId:bundleIdentifier]) {
                    return app;
                }
            }
            else {
                BOOL result = (app->_processIdentifier && kill(app->_processIdentifier, 0) == 0);
                if (!result) {
                    DDLogDebug(@"sharedApplicationForBundleIdentifier 2 attempt: %@, %d", app->_bundleIdentifier, app->_processIdentifier);
                    result = [app runningApplication] != nil;
                }
                if (result) {
                    return app;
                }
                DDLogDebug(@"sharedApplicationForBundleIdentifier remove: %@, %d", app->_bundleIdentifier, app->_processIdentifier);
                [_sharedAppHandler removeObjectForKey:bundleIdentifier];
            }
            return nil;
        }
    }
}

- (instancetype)initWithApplication:(SBApplication *)application bundleIdentifier:(NSString *)bundleIdentifier{
    
    self = [super init];
    if (self) {
        
        _sbApplication = application;
        _bundleIdentifier = bundleIdentifier;
        _processIdentifier = 0;
        _lockForHide = [NSCondition new];
        
        _sbApplication.timeout = COMMAND_TIMEOUT;
    }
    
    return self;
}

- (BOOL)frontmost{

    __block BOOL result = NO;
    [EHSystemUtils callOnMainQueue:^{
        
        NSRunningApplication *frontmostApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
        result = [frontmostApp.bundleIdentifier isEqualToString:self.bundleIdentifier];
    }];
    
    return result;
}

- (pid_t)processIdentifier{
    
    return [[self runningApplication] processIdentifier];
}

- (BOOL)activate{
    [EHSystemUtils callOnMainQueue:^{
        
        self->_wasActivated = [[self runningApplication] activateWithOptions:(NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows)];
    }];
    return _wasActivated;
}

- (BOOL)hide{
    [self->_lockForHide lock];
    [EHSystemUtils callOnMainQueue:^{
        self->_runningApplicationForHide = [self runningApplication];
        [self->_runningApplicationForHide addObserver:self
                                        forKeyPath:@"hidden"
                                           options:NSKeyValueObservingOptionNew context:NULL];
        [self->_runningApplicationForHide hide];
    }];
    [self->_lockForHide waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:COMMAND_TIMEOUT]];
    self->_wasActivated = ! self->_runningApplicationForHide.hidden;
    [self->_runningApplicationForHide removeObserver:self forKeyPath:@"hidden"];
    self->_runningApplicationForHide = nil;
    [self->_lockForHide unlock];
    
    return ! _wasActivated;
}

- (void)makeKeyFrontmostWindow{

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RAISING_WINDOW_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        AXUIElementRef ref = AXUIElementCreateApplication(self.processIdentifier);
        
        if (ref) {
            
            CFIndex count = 0;
            CFArrayRef windowArray = NULL;
            AXError err = AXUIElementGetAttributeValueCount(ref, CFSTR("AXWindows"), &count);
            if (err == kAXErrorSuccess && count) {
                
                err = AXUIElementCopyAttributeValues(ref, CFSTR("AXWindows"), 0, count, &windowArray);
                if (err == kAXErrorSuccess && windowArray) {
                    
                    for ( CFIndex i = 0; i < count; i++){
                        
                        AXUIElementRef window = CFArrayGetValueAtIndex(windowArray, i);
                        if (window) {
                            
                            CFStringRef role;
                            err = AXUIElementCopyAttributeValue(window, CFSTR("AXRole"), (CFTypeRef *)&role);
                            if (err == kAXErrorSuccess && role){
                                
                                if (CFStringCompare(role, CFSTR("AXWindow"), 0) == kCFCompareEqualTo) {
                                
                                    CFStringRef subrole;
                                    err = AXUIElementCopyAttributeValue(window, CFSTR("AXSubrole"), (CFTypeRef *)&subrole);
                                    if (err == kAXErrorSuccess && subrole) {
                                        
                                        if (CFStringCompare(subrole, CFSTR("AXStandardWindow"), 0) == kCFCompareEqualTo) {
                                            AXUIElementPerformAction(window, CFSTR("AXRaise"));
                                            CFRelease(subrole);
                                            CFRelease(role);
                                            break;
                                        }
                                        
                                        CFRelease(subrole);
                                    }
                                }
                                CFRelease(role);
                            }
                        }
                        
                    }
                    
                    CFRelease(windowArray);
                }
            }
            CFRelease(ref);
        }
    });
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Observing properties

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([object isEqual:self->_runningApplicationForHide]) {
        [self->_lockForHide lock];
        if ([keyPath isEqualToString:@"hidden"]) {
            NSNumber *val = change[NSKeyValueChangeNewKey];
            if (val && [val boolValue]) {
                [self->_lockForHide broadcast];
            }
        }
        [self->_lockForHide unlock];
    }
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Supporting actions in application menubar

- (NSString *)menuBarItemNameForIndexPath:(NSIndexPath *)indexPath {
    
    AXUIElementRef menuItem = [self copyMenuBarItemForIndexPath:indexPath];
    
    NSString *name;
    if (menuItem) {
        
        CFTypeRef title;
        name = (AXUIElementCopyAttributeValue(menuItem, (CFStringRef) NSAccessibilityTitleAttribute, (CFTypeRef *)&title) == kAXErrorSuccess ?
                (NSString *)CFBridgingRelease(title): nil);
        
        CFRelease(menuItem);
    }
    
    return name;
}

- (BOOL)pressMenuBarItemForIndexPath:(NSIndexPath *)indexPath {
    
    AXUIElementRef menuItem = [self copyMenuBarItemForIndexPath:indexPath];
    
    BOOL result = NO;
    if (menuItem) {
        
        result = (AXUIElementPerformAction(menuItem, (CFStringRef)NSAccessibilityPressAction) == kAXErrorSuccess);
        CFRelease(menuItem);
    }
    DDLogDebug(@"(pressMenuBarItemForIndexPath) Result: %@", (result ? @"YES" : @"NO"));

    return result;
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Private methods

- (NSRunningApplication *)runningApplication{
    NSRunningApplication *result;
    if (self->_processIdentifier) {
        result = [NSRunningApplication runningApplicationWithProcessIdentifier:self->_processIdentifier];
    }
    else {
        return nil;
    }
    if (result == nil) {
        result = [self runningApplicationCreateFromBundleId:self->_bundleIdentifier];
    }
    return self->_processIdentifier ? [NSRunningApplication runningApplicationWithProcessIdentifier:self->_processIdentifier] : nil;
}

- (NSRunningApplication *)runningApplicationCreateFromBundleId:(NSString *)bundleIdentifier {
    @autoreleasepool {
        NSRunningApplication *runningApp = [[NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] firstObject];
        if (runningApp) {
            self->_processIdentifier = runningApp.processIdentifier;
            self->_sbApplication = [SBApplication applicationWithProcessIdentifier:self->_processIdentifier];
            _sharedAppHandler[bundleIdentifier] = self;
            DDLogDebug(@"runningApplicationCreateFromBundleId add: %@, %d", self->_bundleIdentifier, self->_processIdentifier);

            return runningApp;
        }
        return nil;
    }
}

- (AXUIElementRef)copyMenuBarItemForIndexPath:(NSIndexPath *)indexPath{
    
    if (! indexPath.length) {
        return nil;
    }

    AXUIElementRef item = nil;
    AXUIElementRef ref = AXUIElementCreateApplication(self.processIdentifier);
    
    if (ref) {
        
        CFIndex count = 0;
        CFArrayRef items = nil;
        AXUIElementRef menu = nil;
        BOOL notFound = NO;
        if (AXUIElementCopyAttributeValue(ref, (CFStringRef)NSAccessibilityMenuBarAttribute, (CFTypeRef *)&menu) == kAXErrorSuccess
            && menu) {
            
            item = CFRetain(menu);
            for (NSUInteger i = 0; i < indexPath.length && notFound == NO; i++) {

                //getting submenu if needs it
                if (i) {
                    
                    AXError error = AXUIElementCopyAttributeValues(item, (CFStringRef)NSAccessibilityChildrenAttribute, 0, 1, &items);
                    if (error == kAXErrorSuccess && items) {
                        
                        CFRelease(item);
                        item = CFRetain(CFArrayGetValueAtIndex(items, 0));
                        
                        CFRelease(items);
                    }
                    else {
                        notFound = YES;
                        break;
                    }
                }
                
                NSUInteger index = [indexPath indexAtPosition:i];
                if (AXUIElementGetAttributeValueCount(item, (CFStringRef)NSAccessibilityChildrenAttribute, &count) == kAXErrorSuccess
                    && count > index ) {
                    
                    //getting menu position
                    if (AXUIElementCopyAttributeValues(item, (CFStringRef)NSAccessibilityChildrenAttribute, index, 1, &items) == kAXErrorSuccess
                        && items) {
                        
                        CFRelease(item);
                        item = CFRetain(CFArrayGetValueAtIndex(items, 0));
                        
                        CFRelease(items);
                    }
                    else {
                        
                        notFound = YES;
                    }
                }
                else {
                    
                    notFound = YES;
                }
            }

            if (notFound) {
                
                CFRelease(item);
                item = nil;
            }
            CFRelease(menu);
        }
        
        CFRelease(ref);
    }
    
    return item;
}

- (BOOL)isEqual:(id)object{

    if (object == self)
        return YES;
    if ([object isKindOfClass:[self class]]
        && [_bundleIdentifier isEqualToString:[object bundleIdentifier]])
        return YES;

    return NO;
}

- (NSUInteger)hash
{
    return [_bundleIdentifier hash];
}

@end
