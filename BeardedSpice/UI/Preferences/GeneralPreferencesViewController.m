//
//  GeneralPreferencesViewController.m
//  BeardedSpice
//
//  Created by Jose Falcon on 12/18/13.
//  Copyright (c) 2013 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "GeneralPreferencesViewController.h"
#import "MediaStrategyRegistry.h"
#import "NativeAppTabsRegistry.h"
#import "MediaControllerObject.h"
#import "BSLaunchAtLogin.h"
#import "BSMediaStrategyEnableButton.h"
#import "BSMediaStrategy.h"
#import "BSStrategyCache.h"
#import "BSStrategyVersionManager.h"
#import "EHVerticalCenteredTextField.h"
#import "BSCustomStrategyManager.h"
#import "AppDelegate.h"
#import "EHExecuteBlockDelayed.h"
#import "BSBrowserExtensionsController.h"
#import "Beardie-Swift.h"

#define RELAXING_TIMEOUT                   3 //seconds

NSString *const GeneralPreferencesAutoPauseChangedNoticiation = @"GeneralPreferencesAutoPauseChangedNoticiation";
NSString *const GeneralPreferencesWebSocketServerEnabledChangedNoticiation = @"GeneralPreferencesWebSocketServerEnabledChangedNoticiation";

NSString *const BeardedSpiceAlwaysShowNotification = @"BeardedSpiceAlwaysShowNotification";
NSString *const BeardedSpiceRemoveHeadphonesAutopause = @"BeardedSpiceRemoveHeadphonesAutopause";
NSString *const BeardedSpiceLaunchAtLogin = @"BeardedSpiceLaunchAtLogin";
NSString *const BeardedSpiceUpdateAtLaunch = @"BeardedSpiceUpdateAtLaunch";
NSString *const BeardedSpiceShowProgress = @"BeardedSpiceShowProgress";
NSString *const BeardedSpiceCustomVolumeControl = @"BeardedSpiceCustomVolumeControl";

NSString *const BSWebSocketServerEnabled = @"BSWebSocketServerEnabled";

@implementation GeneralPreferencesViewController

- (id)init{

    self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil];
    if (self) {

    }
    return self;
}

- (void)dealloc{

}

- (NSString *)viewIdentifier
{
    return [GeneralPreferencesViewController className];
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNamePreferencesGeneral];
}

- (NSString *)toolbarItemLabel
{
    return BSLocalizedString(@"General", @"Toolbar item name for the General preference pane");
}

- (void)viewWillAppear{

    [self repairLaunchAtLogin];
}


- (NSView *)initialKeyView{

    return self.firstResponderView;
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Actions
/////////////////////////////////////////////////////////////////////////

- (IBAction)toggleLaunchAtStartup:(id)sender{

    BOOL shouldBeLaunchAtLogin = [[NSUserDefaults standardUserDefaults] boolForKey:BeardedSpiceLaunchAtLogin];
    // We launch Controller of the "Launch at Login" in concurrent queue,
    //because probability exists of hanging app on obtaining list of the login items.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        BSLaunchAtLogin *loginItem = [[BSLaunchAtLogin alloc] initWithIdentifier:BS_LAUNCHER_BUNDLE_ID];
        loginItem.startAtLogin = shouldBeLaunchAtLogin;
    });
}

- (IBAction)toggleAutoPause:(id)sender {

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:GeneralPreferencesAutoPauseChangedNoticiation
         object:self];
    });

}

- (IBAction)toggleWebSocketServer:(id)sender {
    static EHExecuteBlockDelayed *sendNotification;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sendNotification = [[EHExecuteBlockDelayed alloc]
                            initWithTimeout:RELAXING_TIMEOUT
                            leeway:RELAXING_TIMEOUT
                            queue:dispatch_get_main_queue()
                            block:^{
                                [[NSNotificationCenter defaultCenter]
                                 postNotificationName:GeneralPreferencesWebSocketServerEnabledChangedNoticiation
                                 object:self];
                            }];
    });
    NSButton *button = sender;
    BOOL enabled = (button.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:BSWebSocketServerEnabled];
    if (enabled && [[NSUserDefaults standardUserDefaults] boolForKey:BeardieBrowserExtensionsFirstRun]) {
        
        NSAlert *alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = BSLocalizedString(@"install-control-server-cert-title", @"");
        alert.informativeText = BSLocalizedString(@"install-control-server-cert-text", @"");
        [alert addButtonWithTitle:BSLocalizedString(@"continue-button-title", @"Button title")];
        
        [alert addButtonWithTitle:BSLocalizedString(@"cancel-button-title", @"Button title")];
        
        // attach alert to window
        [alert beginSheetModalForWindow:self.view.window
                      completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                [sendNotification executeOnceAfterCalm];
                return;
            }
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:BSWebSocketServerEnabled];
        }];
        return;
    }
    [sendNotification executeOnceAfterCalm];
}

- (IBAction)toggleHideMenuBar:(id)sender {
    [UIController.statusBarMenu updateVisibility];
}

- (IBAction)clickGetExtensions:(id)sender {
    [[BSBrowserExtensionsController singleton] openGetExtensions];
}

/////////////////////////////////////////////////////////////////////////
#pragma mark Private Methods

// Repairs user defaults from login items.
- (void)repairLaunchAtLogin{

    // We launch Controller of the "Launch at Login" in concurrent queue,
    //because probability exists of hanging app on obtaining list of the login items.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        BSLaunchAtLogin *loginItem = [[BSLaunchAtLogin alloc] initWithIdentifier:BS_LAUNCHER_BUNDLE_ID];
        BOOL val = loginItem.startAtLogin;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setBool:val forKey:BeardedSpiceLaunchAtLogin];

        });
    });
}

- (void)displayWarningDialog {
    
}


@end
