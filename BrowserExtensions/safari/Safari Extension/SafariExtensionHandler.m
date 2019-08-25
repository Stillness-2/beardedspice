//
//  SafariExtensionHandler.m
//  Safari Extension
//
//  Created by Roman Sokolov on 29/10/2018.
//  Copyright © 2018 BeardedSpice. All rights reserved.
//

#import "SafariExtensionHandler.h"
#import "BSSharedResources.h"
#import <os/lock.h>
#import "EHLDeferBlock.h"

#define SAFARI_PAGES            @"SafariPages"

@implementation SafariExtensionHandler {
    BOOL _wasActivated;
    SFSafariTab *_previousTab;
    SFSafariTab *_previousTabOnNewWindow;
}

+ (void)resetAllTabs {
    NSLog(@"Reset all tabs invoked.");
    [SFSafariApplication getAllWindowsWithCompletionHandler:^(NSArray<SFSafariWindow *> * _Nonnull windows) {
        for (SFSafariWindow *window in windows) {
            [window getAllTabsWithCompletionHandler:^(NSArray<SFSafariTab *> * _Nonnull tabs) {

                for (SFSafariTab *tab in tabs) {
                    [tab getPagesWithCompletionHandler:^(NSArray<SFSafariPage *> * _Nullable pages) {
                        for (SFSafariPage *page in pages) {
                            [page dispatchMessageToScriptWithName:@"reconnect"
                                                         userInfo:@{@"result": @(YES)}];
                        }
                    }];
                }
            }];
        }
    }];
}
- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)messageReceivedFromContainingAppWithName:(NSString *)messageName
                                        userInfo:(NSDictionary<NSString *,id> *)userInfo {
    NSLog(@"(BeardedSpice Control) received a message (%@) from app with userInfo (%@)", messageName, userInfo);
    [SafariExtensionHandler resetAllTabs];
}
- (void)messageReceivedWithName:(NSString *)messageName fromPage:(SFSafariPage *)page userInfo:(NSDictionary *)userInfo {
    // This method will be called when a content script provided by your extension calls safari.extension.dispatchMessage("message").
    [page getPagePropertiesWithCompletionHandler:^(SFSafariPageProperties *properties) {
        NSLog(@"(BeardedSpice Control) received a message (%@) from a script injected into (%@) with userInfo (%@)", messageName, properties.url, userInfo);
        if (properties.url) {
            if ([messageName isEqualToString:@"accepters"]) {
                //request accepters
                [BSSharedResources acceptersWithCompletion:^(NSDictionary *accepters) {
                    [page dispatchMessageToScriptWithName:@"accepters" userInfo:accepters ?: @{}];
                }];
            }
            else if ([messageName isEqualToString:@"port"]) {
                // request port
                [page dispatchMessageToScriptWithName:@"port" userInfo:@{@"result": @(BSSharedResources.tabPort)}];
            }
            else if ([messageName isEqualToString:@"frontmost"]) {
                [page dispatchMessageToScriptWithName:@"frontmost" userInfo:@{@"result": @(properties.active)}];
            }
            else if ([messageName isEqualToString:@"isActivated"]) {
                [page dispatchMessageToScriptWithName:@"isActivated" userInfo:@{@"result": @(properties.active && self->_wasActivated)}];
            }
            else if ([messageName isEqualToString:@"bundleId"]) {
                [SFSafariApplication getHostApplicationWithCompletionHandler:^(NSRunningApplication * _Nonnull hostApplication) {
                    [page dispatchMessageToScriptWithName:@"bundleId" userInfo:@{@"result": hostApplication.bundleIdentifier}];
                }];
            }
            else if ([messageName isEqualToString:@"serverIsAlive"]) {
                BOOL running = ([NSRunningApplication runningApplicationsWithBundleIdentifier:BS_BUNDLE_ID].count > 0);
                if (running && BSSharedResources.tabPort) {
                    [page dispatchMessageToScriptWithName:@"reconnect" userInfo:@{@"result": @(YES)}];
                }
            }
            else if ([messageName isEqualToString:@"activate"]) {
                [SFSafariApplication getActiveWindowWithCompletionHandler:^(SFSafariWindow * _Nullable activeWindow) {
                    [activeWindow getActiveTabWithCompletionHandler:^(SFSafariTab * _Nullable activeTab) {
                        self->_previousTab = activeTab;
                        [page getContainingTabWithCompletionHandler:^(SFSafariTab * _Nonnull tab) {
                            [tab getContainingWindowWithCompletionHandler:^(SFSafariWindow * _Nullable window) {
                                [window getActiveTabWithCompletionHandler:^(SFSafariTab * _Nullable activeTab) {
                                    self->_previousTabOnNewWindow = activeTab;
                                    if ([self->_previousTabOnNewWindow isEqual:self->_previousTab]) {
                                        self->_previousTabOnNewWindow = nil;
                                    }
                                    [tab activateWithCompletionHandler:^{
                                        self->_wasActivated = YES;
                                        [page dispatchMessageToScriptWithName:@"activate" userInfo:@{@"result": @(YES)}];
                                    }];
                                }];
                            }];
                        }];
                    }];
                }];
            }
            else if ([messageName isEqualToString:@"hide"]) {
                if (properties.active && self->_wasActivated) {
                    void (^activatePreviousTab)(void) = ^void(void) {
                        if (self->_previousTab) {
                            [self->_previousTab activateWithCompletionHandler:^{
                                [page dispatchMessageToScriptWithName:@"hide" userInfo:@{@"result": @(YES)}];
                            }];
                            self->_previousTab = nil;
                            self->_wasActivated = NO;
                        }
                    };
                    if (self->_previousTabOnNewWindow) {
                        [self->_previousTabOnNewWindow activateWithCompletionHandler:^{
                            activatePreviousTab();
                        }];
                        self->_previousTabOnNewWindow = nil;
                    }
                    else {
                        activatePreviousTab();
                    }
                }
            }
//                    else if ([messageName isEqualToString:@"pairing"]) {
//                        BSUtils.storageSet("hostBundleId", theMessageEvent.message.bundleId, () => {
//                            BSUtils.sendMessageToTab(theMessageEvent.target, "pairing", { 'result': true });
//                        });
//                        }
        }
    }];
}

- (void)toolbarItemClickedInWindow:(SFSafariWindow *)window {
    // This method will be called when your toolbar item is clicked.
    NSLog(@"The extension's toolbar item was clicked");
}

- (void)validateToolbarItemInWindow:(SFSafariWindow *)window validationHandler:(void (^)(BOOL enabled, NSString *badgeText))validationHandler {
    // This method will be called whenever some state changes in the passed in window. You should use this as a chance to enable or disable your toolbar item and set badge text.
    validationHandler(YES, nil);
}

- (SFSafariExtensionViewController *)popoverViewController {
    return nil;
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Helper methods

//- (BOOL)setMainAppRunning {
//    @synchronized(self) {
//        _mainAppReady = ([NSRunningApplication runningApplicationsWithBundleIdentifier:BS_BUNDLE_ID].count > 0);
//        return _mainAppReady;
//    }
//}

@end
