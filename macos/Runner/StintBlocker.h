#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// Cooperative app and active-browser-tab guard. Never terminates apps or replaces tabs.
@interface StintBlocker : NSObject
- (instancetype)initWithWindow:(NSWindow *)window
                     messenger:(id<FlutterBinaryMessenger>)messenger;
@end

NS_ASSUME_NONNULL_END
