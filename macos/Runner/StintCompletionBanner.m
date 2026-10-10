#import "StintCompletionBanner.h"
#import <QuartzCore/QuartzCore.h>

static NSFont *StintBannerFont(CGFloat size, NSInteger weight, BOOL mono) {
  NSString *name = mono ? @"MartianMono-SemiExpanded"
      : weight >= 700 ? @"HankenGrotesk-Bold"
      : weight >= 600 ? @"HankenGrotesk-SemiBold" : @"HankenGrotesk-Regular";
  NSFontWeight fallback = weight >= 700 ? NSFontWeightBold
      : weight >= 600 ? NSFontWeightSemibold : NSFontWeightRegular;
  return [NSFont fontWithName:name size:size] ?: (mono
      ? [NSFont monospacedDigitSystemFontOfSize:size weight:fallback]
      : [NSFont systemFontOfSize:size weight:fallback]);
}

static NSString *StintBannerAnnouncement(NSString *title, NSString *body) {
  return [NSString stringWithFormat:@"Stint, %@. %@", title, body];
}

static NSRect StintBannerFrame(NSRect visibleFrame, NSRect anchor, CGFloat height) {
  CGFloat width = MIN(340, MAX(1, NSWidth(visibleFrame) - 24));
  if (NSIsEmptyRect(anchor)) {
    return NSMakeRect(NSMaxX(visibleFrame) - width - 16,
        NSMaxY(visibleFrame) - height - 16, width, height);
  }
  CGFloat x = NSMaxX(anchor) - width;
  CGFloat y = NSMinY(anchor) - 8 - height;
  x = MIN(MAX(x, NSMinX(visibleFrame) + 12), NSMaxX(visibleFrame) - width - 12);
  y = MIN(MAX(y, NSMinY(visibleFrame) + 12), NSMaxY(visibleFrame) - height - 12);
  return NSMakeRect(x, y, width, height);
}

@interface StintBannerPanel : NSPanel
@property(nonatomic, copy) void (^dismissAction)(void);
@property(nonatomic, copy) void (^focusChanged)(void);
@end

@implementation StintBannerPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)cancelOperation:(id)sender { if (self.dismissAction) self.dismissAction(); }
- (void)keyDown:(NSEvent *)event {
  if (event.keyCode == 53) [self cancelOperation:nil];
  else [super keyDown:event];
}
- (void)sendEvent:(NSEvent *)event {
  // Keep this small dialog's explicit button loop available on Macs where
  // Full Keyboard Access otherwise skips ordinary buttons.
  if (event.type == NSEventTypeKeyDown && event.keyCode == 48) {
    if (event.modifierFlags & NSEventModifierFlagShift) [self selectPreviousKeyView:nil];
    else [self selectNextKeyView:nil];
    return;
  }
  [super sendEvent:event];
}
- (void)becomeKeyWindow {
  [super becomeKeyWindow];
  if (self.focusChanged) self.focusChanged();
}
- (void)resignKeyWindow {
  [super resignKeyWindow];
  if (self.focusChanged) self.focusChanged();
}
@end

@interface StintBannerCardView : NSView
@property(nonatomic, copy) void (^hoverChanged)(BOOL);
@property(nonatomic, strong) NSTrackingArea *hoverTracking;
@end

@implementation StintBannerCardView
- (BOOL)isFlipped { return YES; }
- (void)updateTrackingAreas {
  if (self.hoverTracking) [self removeTrackingArea:self.hoverTracking];
  self.hoverTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
      owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTracking];
  [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event { if (self.hoverChanged) self.hoverChanged(YES); }
- (void)mouseExited:(NSEvent *)event { if (self.hoverChanged) self.hoverChanged(NO); }
@end

@interface StintBannerButton : NSButton
@property(nonatomic, strong) NSColor *focusColor;
@end

@implementation StintBannerButton
- (BOOL)needsPanelToBecomeKey { return YES; }
- (BOOL)acceptsFirstResponder { return self.enabled && !self.hidden; }
- (BOOL)canBecomeKeyView { return self.enabled && !self.hidden && !self.isHiddenOrHasHiddenAncestor; }
- (BOOL)becomeFirstResponder {
  BOOL accepted = [super becomeFirstResponder];
  self.needsDisplay = YES;
  return accepted;
}
- (BOOL)resignFirstResponder {
  BOOL accepted = [super resignFirstResponder];
  self.needsDisplay = YES;
  return accepted;
}
- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  if (self.window.isKeyWindow && self.window.firstResponder == self) {
    [(self.focusColor ?: NSColor.keyboardFocusIndicatorColor) setStroke];
    NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2)
                                                      xRadius:18 yRadius:18];
    ring.lineWidth = 2;
    [ring stroke];
  }
}
@end

@interface StintBannerTrack : NSView
@property(nonatomic, copy) NSArray<NSNumber *> *minutes;
@property(nonatomic) NSInteger nextStep;
@property(nonatomic) NSInteger finishedStep;
@property(nonatomic) NSInteger goal;
@property(nonatomic) BOOL goalMet;
@property(nonatomic, copy) NSDictionary<NSString *, NSColor *> *colors;
@end

@implementation StintBannerTrack
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
  NSInteger segments = self.goalMet ? MAX(1, self.goal) : 8;
  CGFloat gap = MIN(3, NSWidth(self.bounds) / (segments * 2));
  CGFloat available = MAX(0, NSWidth(self.bounds) - gap * (segments - 1));
  CGFloat sum = 0;
  for (NSInteger index = 0; index < segments; index++) {
    sum += self.goalMet ? 1 : MAX(1, [self.minutes[index] doubleValue]);
  }
  CGFloat x = 0;
  for (NSInteger index = 0; index < segments; index++) {
    CGFloat minutes = self.goalMet ? 1 : MAX(1, [self.minutes[index] doubleValue]);
    CGFloat width = available * minutes / sum;
    NSRect frame = NSMakeRect(x, 0, width, NSHeight(self.bounds));
    NSColor *phaseColor = self.colors[(self.goalMet || index % 2 == 0) ? @"focus" : @"break"]
        ?: NSColor.controlAccentColor;
    NSColor *fill = self.colors[@"track"] ?: NSColor.separatorColor;
    if (self.goalMet || index == self.finishedStep) fill = phaseColor;
    else if (index < self.nextStep) fill = [phaseColor colorWithAlphaComponent:0.45];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:3 yRadius:3] fill];
    if (!self.goalMet && index == self.nextStep) {
      [phaseColor setStroke];
      NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 0.5, 0.5)
                                                        xRadius:2.5 yRadius:2.5];
      ring.lineWidth = 1;
      [ring stroke];
    }
    x += width + gap;
  }
}
@end

@interface StintCompletionBanner ()
@property(nonatomic, strong) StintBannerPanel *panel;
@property(nonatomic, strong) StintBannerCardView *card;
@property(nonatomic, strong) NSImageView *icon;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *bodyLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
@property(nonatomic, strong) NSImageView *goalCheck;
@property(nonatomic, strong) StintBannerTrack *track;
@property(nonatomic, strong) StintBannerButton *closeButton;
@property(nonatomic, strong) StintBannerButton *actionButton;
@property(nonatomic, strong) StintBannerButton *secondaryButton;
@property(nonatomic, copy) void (^action)(void);
@property(nonatomic, copy) void (^secondaryAction)(void);
@property(nonatomic, readwrite) BOOL hasContent;
@property(nonatomic, readwrite, getter=isHint) BOOL hint;
@property(nonatomic) BOOL temporarilyHidden;
@property(nonatomic) BOOL hovered;
@property(nonatomic) NSUInteger presentation;
@property(nonatomic, strong) NSTimer *hintTimer;
@property(nonatomic, strong) NSDate *hintDeadline;
@property(nonatomic) NSTimeInterval hintRemaining;
@end

@implementation StintCompletionBanner

- (BOOL)isVisible { return self.panel.isVisible; }

- (NSTextField *)labelWithSize:(CGFloat)size weight:(NSInteger)weight {
  NSTextField *label = [NSTextField wrappingLabelWithString:@""];
  label.font = StintBannerFont(size, weight, NO);
  label.selectable = NO;
  return label;
}

- (StintBannerButton *)buttonWithAction:(SEL)action {
  StintBannerButton *button = [[StintBannerButton alloc] initWithFrame:NSZeroRect];
  button.bordered = NO;
  button.bezelStyle = NSBezelStyleInline;
  button.buttonType = NSButtonTypeMomentaryPushIn;
  button.target = self;
  button.action = action;
  button.focusRingType = NSFocusRingTypeNone;
  button.wantsLayer = YES;
  button.layer.cornerRadius = 20;
  return button;
}

- (void)createPanelIfNeeded {
  if (self.panel) return;
  self.panel = [[StintBannerPanel alloc] initWithContentRect:NSMakeRect(0, 0, 340, 200)
      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
      backing:NSBackingStoreBuffered defer:NO];
  self.panel.releasedWhenClosed = NO;
  self.panel.floatingPanel = YES;
  self.panel.becomesKeyOnlyIfNeeded = YES;
  self.panel.hidesOnDeactivate = NO;
  self.panel.level = NSStatusWindowLevel;
  self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
      | NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.panel.opaque = NO;
  self.panel.backgroundColor = NSColor.clearColor;
  self.panel.hasShadow = YES;
  self.panel.animationBehavior = NSWindowAnimationBehaviorNone;
  self.panel.title = @"Stint notification";
  self.panel.autorecalculatesKeyViewLoop = NO;
  self.panel.accessibilitySubrole = NSAccessibilityDialogSubrole;
  __weak StintCompletionBanner *weakSelf = self;
  self.panel.dismissAction = ^{ [weakSelf dismiss]; };
  self.panel.focusChanged = ^{ [weakSelf dismissExpiredHintIfPossible]; };

  self.card = [[StintBannerCardView alloc] initWithFrame:NSMakeRect(0, 0, 340, 200)];
  self.card.wantsLayer = YES;
  self.card.layer.cornerRadius = 18;
  self.card.layer.borderWidth = 1;
  self.card.layer.masksToBounds = NO;
  self.card.hoverChanged = ^(BOOL hovered) {
    weakSelf.hovered = hovered;
    [weakSelf dismissExpiredHintIfPossible];
  };
  self.panel.contentView = self.card;
  self.icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
  self.icon.imageScaling = NSImageScaleProportionallyUpOrDown;
  self.icon.accessibilityElement = NO;
  self.titleLabel = [self labelWithSize:15 weight:700];
  self.bodyLabel = [self labelWithSize:14 weight:400];
  self.detailLabel = [self labelWithSize:12 weight:400];
  self.track = [[StintBannerTrack alloc] initWithFrame:NSZeroRect];
  self.goalCheck = [[NSImageView alloc] initWithFrame:NSZeroRect];
  self.goalCheck.image = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
  self.goalCheck.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold];
  self.goalCheck.accessibilityElement = NO;
  self.closeButton = [self buttonWithAction:@selector(dismissFromButton:)];
  self.closeButton.title = @"";
  self.closeButton.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:nil];
  self.closeButton.imagePosition = NSImageOnly;
  self.closeButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold];
  self.closeButton.accessibilityLabel = @"Dismiss notification";
  self.closeButton.toolTip = @"Dismiss (Escape)";
  self.actionButton = [self buttonWithAction:@selector(startNextFromButton:)];
  self.actionButton.keyEquivalent = @"\r";
  self.actionButton.font = StintBannerFont(14, 700, NO);
  self.secondaryButton = [self buttonWithAction:@selector(secondaryFromButton:)];
  self.secondaryButton.font = StintBannerFont(13, 600, NO);
  self.closeButton.nextKeyView = self.secondaryButton;
  self.secondaryButton.nextKeyView = self.actionButton;
  self.actionButton.nextKeyView = self.closeButton;
  self.panel.initialFirstResponder = self.actionButton;
  for (NSView *view in @[self.icon, self.titleLabel, self.bodyLabel, self.track, self.goalCheck,
                         self.detailLabel, self.closeButton, self.secondaryButton, self.actionButton]) {
    [self.card addSubview:view];
  }
}

- (void)applyColors:(NSDictionary<NSString *, NSColor *> *)colors nextStep:(NSInteger)nextStep {
  NSColor *surface = colors[@"surface"] ?: NSColor.windowBackgroundColor;
  NSColor *accent = colors[nextStep % 2 ? @"break" : @"focus"] ?: NSColor.controlAccentColor;
  NSColor *onAccent = colors[@"onAccent"] ?: NSColor.blackColor;
  self.card.layer.backgroundColor = surface.CGColor;
  self.card.layer.borderColor = (colors[@"line"] ?: NSColor.separatorColor).CGColor;
  NSColor *rgbSurface = [surface colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  BOOL dark = rgbSurface && rgbSurface.redComponent + rgbSurface.greenComponent + rgbSurface.blueComponent < 1.5;
  NSColor *shadow = colors[@"shadow"] ?: [NSColor.blackColor colorWithAlphaComponent:dark ? 0.45 : 0.14];
  self.card.layer.shadowColor = NSColor.blackColor.CGColor;
  self.card.layer.shadowOpacity = shadow.alphaComponent;
  self.card.layer.shadowOffset = CGSizeMake(0, -18);
  self.card.layer.shadowRadius = 24;
  self.titleLabel.textColor = colors[@"ink"] ?: NSColor.labelColor;
  self.bodyLabel.textColor = colors[self.hint ? @"muted" : @"ink2"] ?: NSColor.secondaryLabelColor;
  self.detailLabel.textColor = colors[@"muted"] ?: NSColor.secondaryLabelColor;
  self.closeButton.contentTintColor = colors[@"muted"] ?: NSColor.secondaryLabelColor;
  self.closeButton.focusColor = accent;
  self.actionButton.layer.backgroundColor = accent.CGColor;
  self.actionButton.contentTintColor = onAccent;
  self.actionButton.focusColor = onAccent;
  self.secondaryButton.focusColor = accent;
  self.track.colors = colors;
  self.goalCheck.contentTintColor = colors[@"focusText"] ?: accent;
}

- (void)setButton:(NSButton *)button title:(NSString *)title color:(NSColor *)color size:(CGFloat)size weight:(NSInteger)weight {
  NSDictionary *attributes = @{
    NSFontAttributeName:StintBannerFont(size, weight, NO), NSForegroundColorAttributeName:color,
  };
  NSAttributedString *styledTitle = [[NSAttributedString alloc] initWithString:title attributes:attributes];
  if (button == self.actionButton) {
    // AppKit's inline bezel puts NSImageLeft flush against the pill edge.
    // A single attributed title centers the play symbol and label together.
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightBold]];
    NSImage *tinted = [NSImage imageWithSize:NSMakeSize(11, 12) flipped:NO drawingHandler:^BOOL(NSRect rect) {
      [symbol drawInRect:rect];
      [color setFill];
      NSRectFillUsingOperation(rect, NSCompositingOperationSourceIn);
      return YES;
    }];
    NSTextAttachment *attachment = [NSTextAttachment new];
    attachment.image = tinted;
    attachment.bounds = NSMakeRect(0, -1, 11, 12);
    NSMutableAttributedString *group = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
    [group appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:attributes]];
    [group appendAttributedString:styledTitle];
    styledTitle = group;
  }
  button.image = nil;
  button.imagePosition = NSNoImage;
  button.alignment = NSTextAlignmentCenter;
  button.attributedTitle = styledTitle;
  button.accessibilityLabel = title;
}

- (CGFloat)heightForText:(NSString *)text width:(CGFloat)width font:(NSFont *)font {
  return ceil([text boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
      attributes:@{NSFontAttributeName:font}].size.height) + 2;
}

- (void)placeOnScreen:(NSScreen *)screen anchor:(NSRect)anchor height:(CGFloat)height {
  NSScreen *target = screen ?: NSScreen.mainScreen ?: NSScreen.screens.firstObject;
  NSRect visibleFrame = target ? target.visibleFrame : NSMakeRect(0, 0, 1440, 900);
  [self.panel setFrame:StintBannerFrame(visibleFrame, anchor, height) display:YES];
  self.card.frame = NSMakeRect(0, 0, NSWidth(self.panel.frame), height);
  CGPathRef shadowPath = CGPathCreateWithRoundedRect(self.card.bounds, 18, 18, NULL);
  self.card.layer.shadowPath = shadowPath;
  CGPathRelease(shadowPath);
}

- (void)refreshHoverState {
  NSPoint point = [self.card convertPoint:[self.panel convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
  self.hovered = NSPointInRect(point, self.card.bounds);
}

- (void)showUnlessTemporarilyHidden {
  self.hovered = NO;
  if (!self.temporarilyHidden) {
    [self.panel orderFrontRegardless];
    [self refreshHoverState];
  }
}

- (void)announceTitle:(NSString *)title body:(NSString *)body {
  NSString *announcement = StintBannerAnnouncement(title, body);
  self.panel.accessibilityLabel = announcement;
  if (!self.temporarilyHidden) {
    NSAccessibilityPostNotificationWithUserInfo(NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
      NSAccessibilityAnnouncementKey:announcement,
      NSAccessibilityPriorityKey:@(NSAccessibilityPriorityHigh),
    });
  }
}

- (void)showContent:(NSDictionary *)content colors:(NSDictionary<NSString *, NSColor *> *)colors
             screen:(NSScreen *)screen anchor:(NSRect)anchor action:(void (^)(void))action
    secondaryAction:(void (^)(void))secondaryAction {
  NSAssert(NSThread.isMainThread, @"Completion cards must be presented on the main thread.");
  [self createPanelIfNeeded];
  [self.hintTimer invalidate];
  self.hintTimer = nil;
  self.hintDeadline = nil;
  self.hint = NO;
  self.hasContent = YES;
  self.presentation++;
  self.action = action;
  self.secondaryAction = secondaryAction;
  NSString *title = content[@"title"] ?: @"";
  NSString *body = content[@"body"] ?: @"";
  NSString *detail = content[@"detail"] ?: @"";
  NSString *actionTitle = content[@"actionTitle"] ?: @"Start focus";
  NSString *secondaryTitle = content[@"secondaryTitle"] ?: @"Not now";
  NSInteger nextStep = [content[@"nextStep"] integerValue];
  BOOL goalMet = [content[@"goalMet"] boolValue];
  self.titleLabel.stringValue = title;
  self.titleLabel.font = StintBannerFont(15, 700, NO);
  self.bodyLabel.stringValue = body;
  self.bodyLabel.font = StintBannerFont(14, 400, NO);
  self.icon.image = NSApp.applicationIconImage;
  self.track.minutes = [content[@"stepMinutes"] count] == 8 ? content[@"stepMinutes"] : @[@25,@5,@25,@5,@25,@5,@25,@15];
  self.track.nextStep = nextStep;
  self.track.finishedStep = [content[@"finishedStep"] integerValue];
  self.track.goal = MAX(1, [content[@"goal"] integerValue]);
  self.track.goalMet = goalMet;
  self.track.hidden = NO;
  self.track.needsDisplay = YES;
  self.goalCheck.hidden = !goalMet;
  self.detailLabel.hidden = NO;
  self.actionButton.hidden = NO;
  self.secondaryButton.hidden = NO;
  self.panel.initialFirstResponder = self.actionButton;
  self.closeButton.nextKeyView = self.secondaryButton;
  [self applyColors:colors nextStep:nextStep];
  NSColor *detailColor = colors[goalMet ? @"focusText" : @"muted"] ?: NSColor.secondaryLabelColor;
  NSMutableAttributedString *styledDetail = [[NSMutableAttributedString alloc] initWithString:detail attributes:@{
    NSFontAttributeName:StintBannerFont(12, goalMet ? 600 : 400, NO), NSForegroundColorAttributeName:detailColor,
  }];
  if (!goalMet) {
    NSString *countText = [NSString stringWithFormat:@"%ld of %ld today",
        (long)[content[@"count"] integerValue], (long)[content[@"goal"] integerValue]];
    NSRange countRange = [detail rangeOfString:countText];
    if (countRange.location != NSNotFound) {
      [styledDetail addAttributes:@{NSFontAttributeName:StintBannerFont(12, 400, YES),
          NSForegroundColorAttributeName:colors[@"ink"] ?: NSColor.labelColor} range:countRange];
    }
  }
  self.detailLabel.attributedStringValue = styledDetail;
  self.detailLabel.accessibilityLabel = detail;
  [self setButton:self.actionButton title:actionTitle color:colors[@"onAccent"] ?: NSColor.blackColor size:14 weight:700];
  [self setButton:self.secondaryButton title:secondaryTitle color:colors[@"ink2"] ?: NSColor.secondaryLabelColor size:13 weight:600];

  CGFloat width = 340, innerWidth = width - 18 - 14;
  CGFloat bodyHeight = [self heightForText:body width:innerWidth font:self.bodyLabel.font];
  CGFloat detailWidth = innerWidth - (goalMet ? 20 : 0);
  CGFloat detailHeight = ceil([styledDetail boundingRectWithSize:NSMakeSize(detailWidth, CGFLOAT_MAX)
      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading].size.height) + 2;
  CGFloat bodyY = 16 + 28 + 12;
  CGFloat trackY = bodyY + bodyHeight + 12;
  CGFloat detailY = trackY + 6 + 8;
  CGFloat actionsY = detailY + detailHeight + 12;
  CGFloat height = actionsY + 40 + 14;
  [self placeOnScreen:screen anchor:anchor height:height];
  self.icon.frame = NSMakeRect(18, 16, 28, 28);
  self.closeButton.frame = NSMakeRect(width - 14 - 32, 14, 32, 32);
  self.titleLabel.frame = NSMakeRect(56, 20, width - 14 - 32 - 8 - 56, 24);
  self.bodyLabel.frame = NSMakeRect(18, bodyY, innerWidth, bodyHeight);
  self.track.frame = NSMakeRect(18, trackY, innerWidth, 6);
  self.goalCheck.frame = NSMakeRect(18, detailY + 1, 14, 14);
  self.detailLabel.frame = NSMakeRect(18 + (goalMet ? 20 : 0), detailY, detailWidth, detailHeight);
  CGFloat primaryWidth = ceil([actionTitle sizeWithAttributes:@{NSFontAttributeName:self.actionButton.font}].width) + 18 * 2 + 18;
  CGFloat secondaryWidth = ceil([secondaryTitle sizeWithAttributes:@{NSFontAttributeName:self.secondaryButton.font}].width) + 12;
  self.actionButton.frame = NSMakeRect(width - 14 - primaryWidth, actionsY, primaryWidth, 40);
  self.secondaryButton.frame = NSMakeRect(NSMinX(self.actionButton.frame) - 8 - secondaryWidth, actionsY, secondaryWidth, 40);
  [self showUnlessTemporarilyHidden];
  [self announceTitle:title body:body];
}

- (void)showHintWithColors:(NSDictionary<NSString *, NSColor *> *)colors screen:(NSScreen *)screen anchor:(NSRect)anchor {
  NSAssert(NSThread.isMainThread, @"Hints must be presented on the main thread.");
  [self createPanelIfNeeded];
  [self.hintTimer invalidate];
  self.hintTimer = nil;
  self.hintDeadline = nil;
  self.hint = YES;
  self.hasContent = YES;
  self.presentation++;
  self.action = nil;
  self.secondaryAction = nil;
  self.hintRemaining = 6;
  NSString *title = @"Stint is still running";
  NSString *body = @"Your timer lives in the menu bar. Click it any time.";
  self.titleLabel.stringValue = title;
  self.titleLabel.font = StintBannerFont(14, 700, NO);
  self.bodyLabel.stringValue = body;
  self.bodyLabel.font = StintBannerFont(12, 400, NO);
  self.icon.image = NSApp.applicationIconImage;
  self.track.hidden = YES;
  self.goalCheck.hidden = YES;
  self.detailLabel.hidden = YES;
  self.actionButton.hidden = YES;
  self.secondaryButton.hidden = YES;
  self.closeButton.nextKeyView = self.closeButton;
  self.panel.initialFirstResponder = self.closeButton;
  [self applyColors:colors nextStep:0];
  CGFloat textX = 14 + 28 + 10, textWidth = 340 - textX - 8 - 32 - 4;
  CGFloat titleHeight = [self heightForText:title width:textWidth font:self.titleLabel.font];
  CGFloat bodyHeight = [self heightForText:body width:textWidth font:self.bodyLabel.font];
  CGFloat height = 12 + titleHeight + 4 + bodyHeight + 12;
  [self placeOnScreen:screen anchor:anchor height:height];
  self.icon.frame = NSMakeRect(14, 12, 28, 28);
  self.closeButton.frame = NSMakeRect(340 - 8 - 32, 8, 32, 32);
  self.titleLabel.frame = NSMakeRect(textX, 12, textWidth, titleHeight);
  self.bodyLabel.frame = NSMakeRect(textX, 12 + titleHeight + 4, textWidth, bodyHeight);
  [self showUnlessTemporarilyHidden];
  [self announceTitle:title body:body];
  if (!self.temporarilyHidden) [self startHintTimer];
}

- (void)startHintTimer {
  [self.hintTimer invalidate];
  if (!self.hint || !self.hasContent || self.temporarilyHidden) return;
  self.hintDeadline = [NSDate dateWithTimeIntervalSinceNow:MAX(0, self.hintRemaining)];
  __weak StintCompletionBanner *weakSelf = self;
  self.hintTimer = [NSTimer timerWithTimeInterval:MAX(0.001, self.hintRemaining) repeats:NO block:^(NSTimer *timer) {
    (void)timer;
    weakSelf.hintTimer = nil;
    [weakSelf dismissExpiredHintIfPossible];
  }];
  [NSRunLoop.mainRunLoop addTimer:self.hintTimer forMode:NSRunLoopCommonModes];
}

- (void)dismissExpiredHintIfPossible {
  if (!self.hasContent || !self.hint || self.temporarilyHidden || self.hovered || self.panel.isKeyWindow) return;
  if (self.hintDeadline && self.hintDeadline.timeIntervalSinceNow <= 0) [self dismiss];
}

- (void)setTemporarilyHidden:(BOOL)hidden {
  if (_temporarilyHidden == hidden) return;
  _temporarilyHidden = hidden;
  if (hidden) {
    if (self.hintDeadline) self.hintRemaining = MAX(0, self.hintDeadline.timeIntervalSinceNow);
    [self.hintTimer invalidate];
    self.hintTimer = nil;
    [self.panel orderOut:nil];
  } else if (self.hasContent) {
    [self.panel orderFrontRegardless];
    [self refreshHoverState];
    if (self.hint) [self startHintTimer];
  }
}

- (void)dismissFromButton:(id)sender { [self dismiss]; }

- (void)focusForPreview {
  if (self.panel.isVisible) {
    [self.panel makeKeyWindow];
    [self.panel makeFirstResponder:self.closeButton];
  }
}

- (void)startNextFromButton:(id)sender {
  NSUInteger presentation = self.presentation;
  void (^action)(void) = self.action;
  if (action) action();
  if (self.hasContent && self.presentation == presentation) [self dismiss];
}

- (void)secondaryFromButton:(id)sender {
  NSUInteger presentation = self.presentation;
  void (^action)(void) = self.secondaryAction;
  if (action) action();
  if (self.hasContent && self.presentation == presentation) [self dismiss];
}

- (void)dismiss {
  BOOL hadContent = self.hasContent;
  self.hasContent = NO;
  self.hint = NO;
  self.presentation++;
  [self.hintTimer invalidate];
  self.hintTimer = nil;
  self.hintDeadline = nil;
  self.action = nil;
  self.secondaryAction = nil;
  [self.panel orderOut:nil];
  if (hadContent && self.dismissedHandler) self.dismissedHandler();
}

- (void)dealloc {
  [_hintTimer invalidate];
  [_panel orderOut:nil];
}

@end
