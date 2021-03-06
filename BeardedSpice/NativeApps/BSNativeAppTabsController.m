//
//  BSNativeAppTabsController.m
//  BeardedSpice
//
//  Created by Roman Sokolov on 09.11.17.
//  Copyright (c) 2017 GPL v3 http://www.gnu.org/licenses/gpl.html
//

#import "BSNativeAppTabsController.h"
#import "runningSBApplication.h"
#import "NativeAppTabsRegistry.h"
#import "BSNativeAppTabAdapter.h"
#import "BSTimeout.h"
#import "BSSharedResources.h"
#import "EHExecuteBlockDelayed.h"

@implementation BSNativeAppTabsController {
    
    NSArray <BSNativeAppTabAdapter *> *_tabs;
    BOOL _cacheInvalidated;
    dispatch_queue_t _workQueue;
    NSOperationQueue *_oQueue;
    id _observer;
}

/////////////////////////////////////////////////////////////////////
#pragma mark Initialize

static BSNativeAppTabsController *singletonBSNativeAppTabsController;

+ (BSNativeAppTabsController *)singleton{
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        singletonBSNativeAppTabsController = [BSNativeAppTabsController alloc];
        singletonBSNativeAppTabsController = [singletonBSNativeAppTabsController init];
    });
    
    return singletonBSNativeAppTabsController;
}

- (id)init{
    
    if (singletonBSNativeAppTabsController != self) {
        return nil;
    }
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("NativeAppTabsController", DISPATCH_QUEUE_SERIAL);
        _tabs = [NSArray new];
        
        [self fillCache];
        [[NSWorkspace sharedWorkspace] addObserver:self
                                        forKeyPath:@"runningApplications"
                                           options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew)
                                           context:NULL];
        
        _oQueue = [NSOperationQueue new];
        _oQueue.underlyingQueue = _workQueue;
        ASSIGN_WEAK(self);
        _observer = [[NSNotificationCenter defaultCenter]
                     addObserverForName:BSNativeAppTabsRegistryChangedNotification
                     object:nil queue:_oQueue usingBlock:^(NSNotification * _Nonnull note) {
            ASSIGN_STRONG(self);
            [USE_STRONG(self) fillCache];
        }];
    }
    
    return self;
}

- (void)dealloc{
    
    @try {
        
        [[NSWorkspace sharedWorkspace] removeObserver:self forKeyPath:@"runningApplications"];
    }
    @catch (NSException *exception) {
        // Silent approach.
    }
    [[NSNotificationCenter defaultCenter] removeObserver:_observer];
}
/////////////////////////////////////////////////////////////////////////
#pragma mark Public properties and methods

- (NSArray <BSNativeAppTabAdapter *> *)tabs {
    
    @synchronized (self) {
        if (self->_cacheInvalidated) {
            [self fillCache];
        }
        return [_tabs copy];
    }
}
/////////////////////////////////////////////////////////////////////
#pragma mark Private

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"runningApplications"]) {
        NSIndexSet *indexes = change[NSKeyValueChangeIndexesKey];
        if (indexes) {
            [self fillCache];
        }
    }
}

- (void)fillCache{
    static dispatch_block_t fillBlock;
    static EHExecuteBlockDelayed *slower;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fillBlock = ^{
            
            @autoreleasepool {
                NSMutableArray *tabs = [NSMutableArray new];
                BSTimeout *timeout = [BSTimeout timeoutWithInterval:COMMAND_EXEC_TIMEOUT];
                for (Class nativeApp in [[NativeAppTabsRegistry singleton] enabledNativeAppClasses]) {
                    DDLogDebug(@"(BSNativeAppTabsController - fillCache) native app - %@", [nativeApp bundleId]);
                    runningSBApplication *app = [runningSBApplication sharedApplicationForBundleIdentifier:[nativeApp bundleId]];
                    if (app) {
                        BSNativeAppTabAdapter *tab = [nativeApp tabAdapterWithApplication:app];
                        if (tab) {
                            [tabs addObject:tab];
                        }
                        else {
                            DDLogDebug(@"(BSNativeAppTabsController - fillCache) tab object did not create - %@", [nativeApp bundleId]);
                        }
                    }
                    else {
                        DDLogDebug(@"(BSNativeAppTabsController - fillCache) app object did not create - %@", [nativeApp bundleId]);
                    }
                    if (timeout.reached) {
                        DDLogDebug(@"(BSNativeAppTabsController - fillCache) timeout.reached");
                        break;
                    }
                }
                @synchronized(self) {
                    self->_cacheInvalidated = timeout.reached;
                    self->_tabs = [tabs copy];
                    DDLogDebug(@"(BSNativeAppTabsController - fillCache) cache count - %lu", (unsigned long)self->_tabs.count);
                }
            }
        };
        
        slower = [[EHExecuteBlockDelayed alloc] initWithTimeout:0.5 leeway:0.5 queue:_workQueue block:fillBlock];
    });
    if (_cacheInvalidated) {
        DDLogDebug(@"(BSNativeAppTabsController - fillCache) fill cache sync call");
        dispatch_sync(_workQueue, fillBlock);
    }
    else {
        [slower executeOnceAfterCalm];
    }
}

@end

