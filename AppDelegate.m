// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>
// Modified for MouseRift in 2026: rebranded app identity and added gesture defaults.

#import "AppDelegate.h"
#import "StatusItemController.h"
#import "MouseTap.h"
#import "WelcomeWindowController.h"
#import "PrefsWindowController.h"
#import "DebugWindowController.h"
#import "TestWindowController.h"
#import "TapLogger.h"

NSString *const PrefsReverseScrolling=@"InvertScrollingOn";
NSString *const PrefsReverseHorizontal=@"ReverseX";
NSString *const PrefsReverseVertical=@"ReverseY";
NSString *const PrefsReverseTrackpad=@"ReverseTrackpad";
NSString *const PrefsReverseMouse=@"ReverseMouse";
NSString *const PrefsHasRunBefore=@"HasRunBefore";
NSString *const PrefsHideIcon=@"HideIcon";
NSString *const PrefsBetaUpdates=@"BetaUpdates";
NSString *const PrefsAppcastOverrideURL=@"AppcastOverrideURL";
NSString *const PrefsTerminatedWithPrefsWindowOpen=@"TerminatedWithPrefsWindowOpen";
NSString *const PrefsDiscreteScrollStepSize=@"DiscreteScrollStepSize";
NSString *const PrefsShowDiscreteScrollOptions=@"ShowDiscreteScrollOptions";
NSString *const PrefsMiddleGestures=@"MiddleGestures";
NSString *const PrefsMiddleGestureThreshold=@"MiddleGestureThreshold";
NSString *const PrefsInvertMiddleGestureY=@"InvertMiddleGestureY";
static NSString *const PrefsDidMigrateLegacySettings=@"DidMigrateLegacyScrollSettings";

static void *_contextHideIcon=&_contextHideIcon;
static void *_contextEnabled=&_contextEnabled;
static void *_contextPermissions=&_contextPermissions;

@interface AppDelegate ()
@property MouseTap *tap;
@property StatusItemController *statusController;
@property WelcomeWindowController *welcomeWindowController;
@property PrefsWindowController *prefsWindowController;
@property DebugWindowController *debugWindowController;
@property TestWindowController *testWindowController;
@property PermissionsManager *permissionsManager;
@property LauncherController *launcherController;
@property TapLogger *logger;
@property SPUUpdater *updater;
@property SPUStandardUserDriver *updaterUserDriver;
@property BOOL changingEnabledForPermissions;
@end

@implementation AppDelegate

// note that there is a third category of build, "Development" (see BuildScripts)
+ (NSString *)releaseChannel {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"PilotmoonReleaseChannel"];
}
+ (BOOL)appIsProductionBuild {
    return [[self releaseChannel] isEqualToString:@"Production"];
}
+ (BOOL)appIsBetaBuild {
    return [[self releaseChannel] isEqualToString:@"Beta"];
}

#pragma mark Sparkle

+ (NSString *)sparkleFeedURLString
{
    NSString *urlString=[[NSUserDefaults standardUserDefaults] stringForKey:PrefsAppcastOverrideURL];
    if (!urlString) {
        urlString=@"https://localhost/";
    }
    return urlString ? urlString : @"https://localhost/";
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    return [[self class] sparkleFeedURLString];
}

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)bundle
{
    return NO;
}

- (void)updater:(SPUUpdater *)updater didFinishLoadingAppcast:(SUAppcast *)appcast
{
    NSLog(@"Loaded appcast.");
}

#pragma mark Launch, relaunch and termination

// There can be only one scroll reverser
+ (void)terminateOthers
{
    NSRunningApplication *app=nil;
    for (app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if (![app isEqual:[NSRunningApplication currentApplication]]) {
            if ([[app.bundleIdentifier lowercaseString] isEqualToString:[[NSRunningApplication currentApplication].bundleIdentifier lowercaseString]]) {
                [app terminate];
            }
        }
    }
}

/* Quickly and quietly quit and relaunch our own process. This is called on wake from sleep as a
 workaround for a macOS bug whereby the OS stops calling our event taps after sleep.
 */
- (void)relaunch
{
    [self logAppEvent:@"MouseRift will relaunch"];

    NSWorkspaceOpenConfiguration *config = [[NSWorkspaceOpenConfiguration alloc] init];
    config.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSBundle mainBundle].bundleURL
                                          configuration:config
                                      completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
        if (app) {
            NSLog(@"Launched new instance: %@", app);
        }
        if (error) {
            NSLog(@"Error launching new instance: %@", error);
        }
    }];
}

- (void)handleURLEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent
{
    NSURL* url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
    NSLog(@"Handling URL: %@", url);
    if ([[url scheme] isEqualToString:BUILDSCRIPTS_URL_SCHEME]) {
        if ([[url host] isEqualToString:@"launch"]) {
            NSLog(@"Launch via URL");
        }
    }
}

#pragma mark Inits

+ (void)migrateLegacyPreferences
{
    NSUserDefaults *const defaults=[NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:PrefsDidMigrateLegacySettings]) return;

    NSString *const currentDomain=[[NSBundle mainBundle] bundleIdentifier];
    NSMutableDictionary *current=[([defaults persistentDomainForName:currentDomain] ?: @{}) mutableCopy];
    NSArray *const keys=@[
        PrefsReverseScrolling,
        PrefsReverseHorizontal,
        PrefsReverseVertical,
        PrefsReverseTrackpad,
        PrefsReverseMouse,
        PrefsDiscreteScrollStepSize,
        PrefsShowDiscreteScrollOptions,
        PrefsHideIcon,
    ];
    NSArray *const legacyDomains=@[
        @"com.pilotmoon.scroll-reverser",
        @"com.pilotmoon.ScrollReverser",
        @"com.midswipe.app",
    ];

    for (NSString *domain in legacyDomains) {
        NSDictionary *const legacy=[defaults persistentDomainForName:domain];
        for (NSString *key in keys) {
            id const value=legacy[key];
            if (value && !current[key]) {
                current[key]=value;
                [defaults setObject:value forKey:key];
            }
        }
    }
    [defaults setBool:YES forKey:PrefsDidMigrateLegacySettings];
}

+ (void)initialize
{
    if ([self class]==[AppDelegate class])
    {
        [self migrateLegacyPreferences];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            PrefsReverseScrolling: @(YES),
            PrefsReverseHorizontal: @(NO),
            PrefsReverseVertical: @(YES),
            PrefsReverseTrackpad: @(NO),
            PrefsReverseMouse: @(YES),
            PrefsDiscreteScrollStepSize: @(3),
            PrefsMiddleGestures: @(YES),
            PrefsMiddleGestureThreshold: @(80),
            PrefsInvertMiddleGestureY: @(NO),
            LoggerMaxEntries: @(50000),
            PrefsBetaUpdates: @([self appIsBetaBuild]),
        }];
    }
}

- (id)init
{
    self=[super init];
    if (self) {
        [[self class] terminateOthers];

        self.tap=[[MouseTap alloc] init];

        self.launcherController=[[LauncherController alloc] init];

        self.statusController=[[StatusItemController alloc] init];
        self.statusController.statusItemDelegate=self;
        self.statusController.visible=![[NSUserDefaults standardUserDefaults] boolForKey:PrefsHideIcon];
        [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:PrefsHideIcon options:0 context:_contextHideIcon];

        self.permissionsManager=[[PermissionsManager alloc] init];

        NSBundle *const hostBundle = [NSBundle mainBundle];
        self.updaterUserDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self];
        self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:hostBundle userDriver:self.updaterUserDriver delegate:self];
        NSError *error=nil;
        if (![self.updater startUpdater:&error]) {
            NSLog(@"Updater failed to start: %@", error);
        }
        else {
            NSLog(@"Updater started");
        }

        // event handler for url events (for launching)
        [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                           andSelector:@selector(handleURLEvent:withReplyEvent:)
                                                         forEventClass:kInternetEventClass
                                                            andEventID:kAEGetURL];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark Application events

- (void)awakeFromNib {
    [self.statusController attachMenu:self.statusMenu];
}
    
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Even though the app has no visible main menu, we set a minimal menu for keyboard shortcut support.
    // For example, ⌘W to close the prefs window.
    [NSApp setMainMenu:self.theMainMenu];

    // Show the welcome window if the user hasn't run MouseRift before.
    const BOOL first=![[NSUserDefaults standardUserDefaults] boolForKey:PrefsHasRunBefore];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PrefsHasRunBefore];
    if(first) {
        self.welcomeWindowController=[[WelcomeWindowController alloc] initWithWindowNibName:@"WelcomeWindow"];
        [self.welcomeWindowController showWindow:self];
    }
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(appDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(appWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    
    // Observe permissions updates
    [self.permissionsManager addObserver:self
                              forKeyPath:PermissionsManagerKeyHasAllRequiredPermissions
                                 options:NSKeyValueObservingOptionInitial
                                 context:_contextPermissions];
    [self logAppEvent:@"MouseRift started. Option-click the MouseRift menu bar icon to show the debug console."];

    // We don't bind `enabled` directly to prefs, because of the many dynamic interactions with the setting.
    const BOOL enabledInPrefs=[[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseScrolling];
    [self addObserver:self forKeyPath:@"enabled" options:0 context:_contextEnabled];
    if (enabledInPrefs && self.permissionsManager.hasAllRequiredPermissions) {
        self.enabled=YES;
    }
    self.statusController.enabled=self.enabled;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:PrefsTerminatedWithPrefsWindowOpen]) {
        [self showPrefs:self];
    }
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:PrefsTerminatedWithPrefsWindowOpen];
}

- (void)appDidWake:(NSNotification *)note
{
    [self logAppEvent:@"OS woke from sleep - will relaunch"];
    [self relaunch];
}

- (void)appWillSleep:(NSNotification *)note
{
    [self logAppEvent:@"OS is going to sleep"];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self logAppEvent:@"MouseRift will terminate"];
    if (self.prefsWindowController.window.visible) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PrefsTerminatedWithPrefsWindowOpen];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag
{
    [self showPrefs:nil];
    return NO;
}

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key // For Applescript handling
{
    return [key isEqualToString:@"enabled"];
}

#pragma mark Logging

- (NSString *)settingsSummary
{
    NSString *(^yn)(NSString *, BOOL) = ^(NSString *label, BOOL state) {
        return [NSString stringWithFormat:@"[%@ %@]", label, state?@"yes":@"no"];
    };
    NSString *temp=yn(@"on", [[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseScrolling]);
    temp=[temp stringByAppendingString:yn(@"v", [[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseVertical])];
    temp=[temp stringByAppendingString:yn(@"h", [[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseHorizontal])];
    temp=[temp stringByAppendingString:yn(@"trackpad", [[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseTrackpad])];
    temp=[temp stringByAppendingString:yn(@"mouse", [[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseMouse])];
    return temp;
}

- (Logger *)startLogging
{
    if (!self.logger) {
        self.logger=[[TapLogger alloc] init];
        self.tap->logger=self.logger;
    }
    return self.logger;
}

- (void)logAppEvent:(NSString *)str
{
    NSString *message=[NSString stringWithFormat:@"%@ %@", str, [self settingsSummary]];
    NSLog(@"App event: %@", message);
    [self.logger logMessage:message special:YES];
}

#pragma mark Showing windows

- (IBAction)showDebug:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    if(!self.debugWindowController) {
        self.debugWindowController=[[DebugWindowController alloc] initWithWindowNibName:@"DebugWindow"];
        self.debugWindowController.logger=[self startLogging];
    }
    [self.debugWindowController showWindow:self];
}

- (void)showPrefsWithDefaultPane:(BOOL)showDefault
{
    [NSApp activateIgnoringOtherApps:YES];
    if(!self.prefsWindowController) {
        self.prefsWindowController=[[PrefsWindowController alloc] initWithWindowNibName:@"PrefsWindow"];
    }
    if (showDefault) {
        [self.prefsWindowController showPermissionsPane];
    }
    [self.prefsWindowController showWindow:self];
}

- (IBAction)showPrefs:(id)sender
{
    [self showPrefsWithDefaultPane:NO];
}

- (IBAction)showAbout:(id)sender
{
    [self.prefsWindowController close];
    [NSApp activateIgnoringOtherApps:YES];
    NSDictionary *dict=@{@"ApplicationName": @"MouseRift"};
    [NSApp orderFrontStandardAboutPanelWithOptions:dict];
}

- (IBAction)showTestWindow:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    if(!self.testWindowController) {
        self.testWindowController=[[TestWindowController alloc] initWithWindowNibName:@"TestWindow"];
    }
    [self.testWindowController showWindow:self];
}

#pragma mark Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context==_contextHideIcon) {
        self.statusController.visible=![[NSUserDefaults standardUserDefaults] boolForKey:PrefsHideIcon];;
    }
    else if (context==_contextEnabled) {
        self.statusController.enabled=self.enabled;
        if (!self.changingEnabledForPermissions) {
            [[NSUserDefaults standardUserDefaults] setBool:self.enabled forKey:PrefsReverseScrolling];
        }
    }
    else if (context==_contextPermissions) {
        self.changingEnabledForPermissions=YES;
        if(!self.permissionsManager.hasAllRequiredPermissions) {
            self.enabled=NO;
        }
        else if ([[NSUserDefaults standardUserDefaults] boolForKey:PrefsReverseScrolling]) {
            self.enabled=YES;
        }
        self.changingEnabledForPermissions=NO;
        self.statusController.enabled=self.enabled;
    }
}

#pragma mark Enable/disable

- (void)setEnabled:(BOOL)state
{
    if (state==self.enabled) { // already in this state
        return;
    }

    if ((!state) || self.permissionsManager.hasAllRequiredPermissions) {
        [self logAppEvent:[NSString stringWithFormat:@"Setting enabled state to: %@", @(state)]];
        self.tap.active=state;
    }
    else {
        if (state) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:PrefsReverseScrolling];
        }
        [self logAppEvent:@"Cannot enable MouseRift; missing required permissions"];
    }

    // in case changing active state fails, force refresh of the triggering button
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self willChangeValueForKey:@"enabled"];
        [self didChangeValueForKey:@"enabled"];
        if (state && (!self.enabled)) { // failed to enable
            [self showPermissionsUI];
        }
    });
}

- (BOOL)isEnabled {
    return self.tap.active;
}

+ (NSSet *)keyPathsForValuesAffectingEnabled {
    return [NSSet setWithObject:@"tap.active"];
}

#pragma mark Status item handling

- (void)statusItemClicked {
    // do nothing
}

- (void)statusItemRightClicked {
    self.enabled=!self.enabled; // toggle
}

- (void)statusItemAltClicked {
    [self showDebug:self];
}

#pragma mark Permissions

- (void)refreshPermissions {
    [self.permissionsManager refresh];
}

- (void)showPermissionsUI {
    [self showPrefsWithDefaultPane:YES];
}

#pragma mark Special

- (void)enableDiscreteScrollOptions
{
    [[NSUserDefaultsController sharedUserDefaultsController] setValue:@YES forKeyPath:@"values.ShowDiscreteScrollOptions"];
}

#pragma mark App info strings

- (NSString *)appName {
    return @"MouseRift";
}

- (NSString *)appVersion {
    return [NSString stringWithFormat:@"%@ (%@)",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
}

- (NSString *)appCredit {
    return @"MouseRift contributors · based on Scroll Reverser by Nick Moore";
}

- (NSURL *)appLink {
    return [NSURL URLWithString:@"https://github.com/bramblex/MouseRift"];
}

- (NSString *)appDisplayLink {
    return @"github.com/bramblex/MouseRift";
}

- (NSURL *)appPermissionsHelpLink {
    return [NSURL URLWithString:@"https://github.com/bramblex/MouseRift#permissions"];
}

#pragma mark Other UI Strings

- (NSString *)menuStringReverseScrolling {
    return [NSString stringWithFormat:NSLocalizedString(@"Enable %1$@", @"1=name of app e.g. `Enable Scroll Reverser`"), self.appName];
}
- (NSString *)menuStringPreferences {
    return [NSLocalizedString(@"Preferences", nil) stringByAppendingString:@"..."];
}
- (NSString *)menuStringQuit {
    return [NSString stringWithFormat:NSLocalizedString(@"Quit %1$@",@"1=name of app e.g. `Quit Scroll Reverser`"`), self.appName];
}

@end
