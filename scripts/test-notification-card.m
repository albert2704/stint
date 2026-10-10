// Exercises production card lifetime and placement without opening an AppKit window.
#import <Cocoa/Cocoa.h>
#import "../macos/Runner/DeskCompletionBanner.m"

static NSInteger checks;
static void Check(BOOL value, NSString *message) {
  checks++;
  if (!value) {
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
  }
}

@interface CardPanelProbe : NSObject
@property(nonatomic, getter=isVisible) BOOL visible;
@property(nonatomic, getter=isKeyWindow) BOOL keyWindow;
@property(nonatomic) NSInteger hides;
@property(nonatomic) NSInteger shows;
@end
@implementation CardPanelProbe
- (void)orderOut:(id)sender { self.visible = NO; self.hides++; }
- (void)orderFrontRegardless { self.visible = YES; self.shows++; }
@end

@interface CardProbe : DeskCompletionBanner
@end
@implementation CardProbe
- (void)refreshHoverState { self.hovered = NO; }
@end

static CardProbe *NewCard(BOOL hint) {
  CardProbe *card = [CardProbe new];
  CardPanelProbe *panel = [CardPanelProbe new];
  panel.visible = YES;
  card.panel = (DeskBannerPanel *)(id)panel;
  card.hasContent = YES;
  card.hint = hint;
  card.presentation = 1;
  return card;
}

int main(void) {
  @autoreleasepool {
    NSRect screen = NSMakeRect(0, 0, 1440, 876);
    NSRect anchor = NSMakeRect(1210, 876, 60, 24);
    NSRect frame = DeskBannerFrame(screen, anchor, 214);
    Check(NSWidth(frame) == 340, @"card is 340 pixels wide");
    Check(NSMaxX(frame) == NSMaxX(anchor), @"right edge follows status item");
    Check(NSMaxY(frame) == NSMaxY(screen) - 12, @"top respects visible-frame clamp");
    frame = DeskBannerFrame(screen, NSMakeRect(1210, 820, 60, 24), 214);
    Check(NSMaxY(frame) == 812, @"unclamped anchor leaves eight pixels below item");
    frame = DeskBannerFrame(screen, NSMakeRect(0, 820, 30, 24), 214);
    Check(NSMinX(frame) == 12, @"left edge clamps twelve pixels inside screen");
    frame = DeskBannerFrame(screen, NSMakeRect(1430, 820, 30, 24), 214);
    Check(NSMaxX(frame) == 1428, @"right edge clamps twelve pixels inside screen");
    frame = DeskBannerFrame(screen, NSMakeRect(800, 10, 30, 24), 214);
    Check(NSMinY(frame) == 12, @"bottom edge clamps twelve pixels inside screen");
    frame = DeskBannerFrame(screen, NSZeroRect, 214);
    Check(NSMaxX(frame) == 1424 && NSMaxY(frame) == 860, @"missing status item uses sixteen-pixel fallback");
    frame = DeskBannerFrame(NSMakeRect(-1728, 100, 1728, 1077), NSMakeRect(-200, 1177, 60, 24), 198);
    Check(NSMaxX(frame) == -140 && NSMaxY(frame) == 1165, @"secondary screens retain global coordinates");
    Check([DeskBannerAnnouncement(@"Focus complete", @"Your short break is ready.")
        isEqualToString:@"Stint, Focus complete. Your short break is ready."], @"announcement and dialog label include app, title and body");

    CardProbe *card = NewCard(NO);
    CardPanelProbe *panel = (id)card.panel;
    __block NSInteger dismissals = 0, starts = 0;
    card.dismissedHandler = ^{ dismissals++; };
    card.action = ^{ starts++; };
    [card setTemporarilyHidden:YES];
    Check(!card.visible && card.hasContent, @"panel opening hides without discarding completion");
    Check(card.action != nil && dismissals == 0, @"temporary hide retains action and does not notify dismissal");
    [card setTemporarilyHidden:NO];
    Check(card.visible && panel.shows == 1, @"panel closing restores completion");
    [card setTemporarilyHidden:NO];
    Check(panel.shows == 1, @"unchanged visibility does not present twice");
    [card startNextFromButton:nil];
    Check(starts == 1 && dismissals == 1 && !card.hasContent, @"primary action invokes callback and dismisses once");
    [card setTemporarilyHidden:YES];
    [card setTemporarilyHidden:NO];
    Check(!card.visible, @"dismissed card never restores");
    [card dismiss];
    Check(dismissals == 1, @"repeated dismissal does not notify twice");

    card = NewCard(NO);
    __block BOOL contextValid = YES, ranWithContext = NO;
    card.dismissedHandler = ^{ contextValid = NO; };
    card.action = ^{ ranWithContext = contextValid; };
    [card startNextFromButton:nil];
    Check(ranWithContext && !contextValid, @"primary callback precedes context-clearing dismissal");
    card = NewCard(NO);
    contextValid = YES;
    ranWithContext = NO;
    card.dismissedHandler = ^{ contextValid = NO; };
    card.secondaryAction = ^{ ranWithContext = contextValid; };
    [card secondaryFromButton:nil];
    Check(ranWithContext && !contextValid, @"secondary callback precedes context-clearing dismissal");

    card = NewCard(NO);
    __weak CardProbe *weakCard = card;
    card.action = ^{ weakCard.presentation++; };
    [card startNextFromButton:nil];
    Check(card.hasContent, @"synchronous replacement survives old primary callback");
    card.secondaryAction = ^{ weakCard.presentation++; };
    [card secondaryFromButton:nil];
    Check(card.hasContent, @"synchronous replacement survives old secondary callback");
    [card dismiss];

    card = NewCard(YES);
    panel = (id)card.panel;
    card.hintRemaining = 6;
    [card startHintTimer];
    Check(card.hintTimer != nil && card.hintTimer.isValid, @"hint timeout is scheduled");
    NSTimeInterval delay = card.hintTimer.fireDate.timeIntervalSinceNow;
    Check(delay > 5.8 && delay <= 6, @"hint waits six seconds");
    [card dismissExpiredHintIfPossible];
    Check(card.hasContent, @"hint survives before six seconds");
    card.hintDeadline = [NSDate dateWithTimeIntervalSinceNow:-1];
    card.hovered = YES;
    [card dismissExpiredHintIfPossible];
    Check(card.hasContent, @"expired hint stays while hovered");
    card.hovered = NO;
    panel.keyWindow = YES;
    [card dismissExpiredHintIfPossible];
    Check(card.hasContent, @"expired hint stays while keyboard focused");
    panel.keyWindow = NO;
    [card dismissExpiredHintIfPossible];
    Check(!card.hasContent && !card.visible && card.hintTimer == nil, @"expired hint dismisses when hover and focus leave");

    card = NewCard(YES);
    card.hintRemaining = 6;
    [card startHintTimer];
    card.hintDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
    [card setTemporarilyHidden:YES];
    Check(card.hintTimer == nil && card.hintRemaining > 2.8 && card.hintRemaining <= 3,
        @"opening panel pauses remaining hint lifetime");
    card.hintDeadline = [NSDate dateWithTimeIntervalSinceNow:-1];
    [card dismissExpiredHintIfPossible];
    Check(card.hasContent, @"hidden hint cannot expire");
    [card setTemporarilyHidden:NO];
    Check(card.visible && card.hintTimer.fireDate.timeIntervalSinceNow > 2.8,
        @"closing panel resumes remaining hint lifetime");
    [card dismiss];

    card = NewCard(NO);
    card.hintDeadline = [NSDate dateWithTimeIntervalSinceNow:-1];
    [card dismissExpiredHintIfPossible];
    Check(card.hasContent, @"completion never inherits hint timeout");
    [card startHintTimer];
    Check(card.hintTimer == nil, @"completion cannot schedule auto-dismiss");
    [card dismiss];
    printf("Notification card: %ld checks passed\n", (long)checks);
  }
  return 0;
}
