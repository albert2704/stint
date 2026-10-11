// Local development host for machines with Command Line Tools but no full Xcode.
// The regular Flutter macOS project remains the supported release build path.
#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>
#import <UserNotifications/UserNotifications.h>
#import "../macos/Runner/StintMenuBar.h"
#import "../macos/Runner/StintMusic.h"
#import "../macos/Runner/StintBlocker.h"

static NSURL *StintDirectory(NSError **error) {
  NSURL *support = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
      inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:error];
  if (!support) return nil;
  NSURL *directory = [support URLByAppendingPathComponent:@"Stint" isDirectory:YES];
  if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  return directory;
}

static FlutterError *StintError(NSString *code, NSError *error) {
  return [FlutterError errorWithCode:code message:error.localizedDescription details:nil];
}

static NSImage *StintIcon(void) {
  return [[NSImage alloc] initWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"AppIcon" withExtension:@"icns"]];
}

@interface StintWindow : NSWindow
@property(nonatomic, weak) StintMenuBar *menuBar;
@end
@implementation StintWindow
- (void)close { [self.menuBar windowWillClose]; [self orderOut:nil]; }
@end

@interface StintDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) FlutterViewController *controller;
@property(nonatomic, strong) FlutterMethodChannel *files;
@property(nonatomic, strong) StintMenuBar *menuBar;
@property(nonatomic, strong) StintMusic *music;
@property(nonatomic, strong) StintBlocker *blocker;
@end

@implementation StintDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.controller = [[FlutterViewController alloc] initWithProject:nil];
  self.window = [[StintWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 758)
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
  self.window.title = @"Stint";
  self.window.contentMinSize = NSMakeSize(420, 600);
  self.window.releasedWhenClosed = NO;
  self.window.contentViewController = self.controller;
  [self.window center];
  self.files = [FlutterMethodChannel methodChannelWithName:@"stint/files" binaryMessenger:self.controller.engine.binaryMessenger];
  __weak StintDelegate *weakSelf = self;
  [self.files setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    StintDelegate *self = weakSelf;
    if (!self) { result([FlutterError errorWithCode:@"closed" message:@"Window closed." details:nil]); return; }
    NSError *error = nil;
    if ([call.method isEqualToString:@"dataDirectory"]) {
      NSURL *directory = StintDirectory(&error);
      if (!directory) { result(StintError(@"storage_failed", error)); return; }
      result(directory.path);
    } else { result(FlutterMethodNotImplemented); }
  }];
  NSMenu *menu = [[NSMenu alloc] init];
  NSMenuItem *appItem = [[NSMenuItem alloc] init]; [menu addItem:appItem];
  NSMenu *app = [[NSMenu alloc] initWithTitle:@"Stint"];
  [app addItemWithTitle:@"About Stint" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [app addItem:NSMenuItem.separatorItem];
  [app addItemWithTitle:@"Hide Stint" action:@selector(hide:) keyEquivalent:@"h"];
  [app addItemWithTitle:@"Quit Stint" action:@selector(terminate:) keyEquivalent:@"q"];
  appItem.submenu = app;
  NSMenuItem *editItem = [[NSMenuItem alloc] init]; [menu addItem:editItem];
  NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
  [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  NSMenuItem *redo = [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"]; redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
  [edit addItem:NSMenuItem.separatorItem];
  [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  editItem.submenu = edit;
  NSApp.mainMenu = menu;
  NSApp.applicationIconImage = StintIcon();
  self.menuBar = [[StintMenuBar alloc] initWithWindow:self.window messenger:self.controller.engine.binaryMessenger];
  ((StintWindow *)self.window).menuBar = self.menuBar;
  self.music = [[StintMusic alloc] initWithWindow:self.window messenger:self.controller.engine.binaryMessenger];
  self.blocker = [[StintBlocker alloc] initWithWindow:self.window messenger:self.controller.engine.binaryMessenger];
  self.music.youTubeViewChanged = ^(NSView *view) {
    [weakSelf.menuBar setYouTubeView:view];
  };
  self.music.showYouTubePlayer = ^{
    [weakSelf.menuBar showYouTubePlayer];
  };
  self.menuBar.youTubeVisibilityChanged = ^(BOOL visible) {
    [weakSelf.music youTubeVisibilityChanged:visible];
  };
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  [self.menuBar showWindow];
  return YES;
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }
@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    // Read-only diagnostics for native verification of this development bundle.
    if (argc == 2 && strcmp(argv[1], "--notification-status") == 0) {
      __block BOOL complete = NO;
      UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
      [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
          [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *pending) {
            NSMutableArray *titles = [NSMutableArray array];
            for (UNNotification *notification in delivered) [titles addObject:notification.request.content.title];
            NSDictionary *status = @{@"authorization": @(settings.authorizationStatus), @"alertSetting": @(settings.alertSetting), @"soundSetting": @(settings.soundSetting), @"delivered": titles, @"pendingCount": @(pending.count)};
            NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            dispatch_async(dispatch_get_main_queue(), ^{ complete = YES; });
          }];
        }];
      }];
      NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
      while (!complete && limit.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
      return complete ? 0 : 1;
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    StintDelegate *delegate = [[StintDelegate alloc] init];
    NSApp.delegate = delegate;
    [NSApp run];
  }
  return 0;
}
