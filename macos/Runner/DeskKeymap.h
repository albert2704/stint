#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns saved shortcuts and their macOS registration. No input permission needed.
@interface DeskKeymap : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          action:(void (^)(NSString *action))action;
- (BOOL)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
