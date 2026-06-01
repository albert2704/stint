#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A Stint card that can appear without activating the main app.
@interface DeskCompletionBanner : NSObject
@property(nonatomic, readonly, getter=isVisible) BOOL visible;
@property(nonatomic, readonly) BOOL hasContent;
@property(nonatomic, readonly, getter=isHint) BOOL hint;
/// Called for an explicit dismissal or the hint timeout, never for a temporary hide.
@property(nonatomic, copy, nullable) void (^dismissedHandler)(void);
/// Content includes title, body, detail, actionTitle, secondaryTitle, nextStep,
/// finishedStep, stepMinutes, count, goal, and goalMet. Anchor is in screen coordinates.
- (void)showContent:(NSDictionary *)content
             colors:(NSDictionary<NSString *, NSColor *> *)colors
             screen:(nullable NSScreen *)screen
             anchor:(NSRect)anchor
             action:(void (^)(void))action
    secondaryAction:(void (^)(void))secondaryAction;
- (void)showHintWithColors:(NSDictionary<NSString *, NSColor *> *)colors
                  screen:(nullable NSScreen *)screen
                  anchor:(NSRect)anchor;
/// Hides without discarding the card or its callbacks. Hidden hint time is paused.
- (void)setTemporarilyHidden:(BOOL)hidden;
- (void)dismiss;
/// A menu-requested preview may take keyboard focus; timed alerts never do.
- (void)focusForPreview;
@end

NS_ASSUME_NONNULL_END
