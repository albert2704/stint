#import "StintKeymap.h"
#import <Carbon/Carbon.h>
#import <math.h>

static NSString *const StintKeymapPreference = @"StintKeyboardShortcuts";
static const OSType StintKeymapSignature = 'STNT';

static NSArray<NSString *> *StintShortcutActions(void) {
  return @[@"toggle", @"reset", @"skip", @"panel"];
}

static NSString *StintShortcutActionName(NSString *action) {
  return @{@"toggle": @"Start/Pause", @"reset": @"Reset", @"skip": @"Skip",
           @"panel": @"Show timer panel"}[action] ?: action;
}

static NSDictionary<NSNumber *, NSString *> *StintShortcutKeys(void) {
  static NSDictionary *keys;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    keys = @{@0:@"A", @1:@"S", @2:@"D", @3:@"F", @4:@"H", @5:@"G",
             @6:@"Z", @7:@"X", @8:@"C", @9:@"V", @11:@"B", @12:@"Q",
             @13:@"W", @14:@"E", @15:@"R", @16:@"Y", @17:@"T", @18:@"1",
             @19:@"2", @20:@"3", @21:@"4", @22:@"6", @23:@"5", @25:@"9",
             @26:@"7", @28:@"8", @29:@"0", @31:@"O", @32:@"U", @34:@"I",
             @35:@"P", @37:@"L", @38:@"J", @40:@"K", @45:@"N", @46:@"M",
             @49:@"Space", @122:@"F1", @120:@"F2", @99:@"F3", @118:@"F4",
             @96:@"F5", @97:@"F6", @98:@"F7", @100:@"F8", @101:@"F9",
             @109:@"F10", @103:@"F11", @111:@"F12", @123:@"←", @124:@"→",
             @125:@"↓", @126:@"↑"};
  });
  return keys;
}

static BOOL StintShortcutInteger(id value) {
  return [value isKindOfClass:NSNumber.class] &&
      CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
      isfinite([value doubleValue]) && [value doubleValue] == [value integerValue];
}

static NSUInteger StintShortcutModifiers(NSEventModifierFlags flags) {
  return ((flags & NSEventModifierFlagControl) ? 1 : 0) |
      ((flags & NSEventModifierFlagOption) ? 2 : 0) |
      ((flags & NSEventModifierFlagShift) ? 4 : 0) |
      ((flags & NSEventModifierFlagCommand) ? 8 : 0);
}

static UInt32 StintShortcutCarbonModifiers(NSUInteger bits) {
  return ((bits & 1) ? controlKey : 0) | ((bits & 2) ? optionKey : 0) |
      ((bits & 4) ? shiftKey : 0) | ((bits & 8) ? cmdKey : 0);
}

static BOOL StintShortcutReserved(NSInteger key, NSUInteger modifiers) {
  // Keep standard editing/menu commands, app hiding/quit, input switching,
  // screenshots, screen locking, and Mission Control available to macOS/apps.
  if ((modifiers & 8) && (key == 12 || key == 4 || key == 46 || key == 43 || key == 49)) return YES;
  if (modifiers == 9 && key == 3) return YES; // Control Command F: full screen.
  if ((modifiers == 1 || modifiers == 5) && key == 49) return YES;
  if ((modifiers == 1 || modifiers == 5) && key >= 123 && key <= 126) return YES;
  if (modifiers == 1 && [@[@120, @99, @118, @96, @97, @98, @100] containsObject:@(key)]) return YES;
  if ((modifiers == 12 || modifiers == 14) && [@[@20, @21, @23, @22] containsObject:@(key)]) return YES;
  if (modifiers == 8 || modifiers == 12 || modifiers == 10 || modifiers == 14) {
    NSString *name = StintShortcutKeys()[@(key)];
    NSSet *menuKeys = [NSSet setWithArray:@[@"A", @"B", @"C", @"D", @"E", @"F", @"G", @"I",
        @"K", @"L", @"N", @"O", @"P", @"R", @"S", @"T", @"U", @"V", @"W", @"X", @"Y", @"Z"]];
    if ([menuKeys containsObject:name]) return YES;
    if (modifiers == 8 && [@[@18,@19,@20,@21,@22,@23,@25,@26,@28,@29] containsObject:@(key)]) return YES;
  }
  return NO;
}

static NSDictionary *StintShortcutBinding(id value, NSString **error) {
  if (![value isKindOfClass:NSDictionary.class] || !StintShortcutInteger(value[@"keyCode"]) ||
      !StintShortcutInteger(value[@"modifiers"])) {
    if (error) *error = @"A shortcut must contain a supported key and valid modifiers.";
    return nil;
  }
  NSInteger key = [value[@"keyCode"] integerValue];
  NSInteger bits = [value[@"modifiers"] integerValue];
  if (bits < 0 || (bits & ~15) || !(bits & (1 | 8))) {
    if (error) *error = @"Include Control or Command in each shortcut.";
    return nil;
  }
  if (StintShortcutReserved(key, bits)) {
    if (error) *error = @"That shortcut is reserved for macOS or standard app commands. Choose another combination.";
    return nil;
  }
  NSString *name = StintShortcutKeys()[@(key)];
  if (!name) {
    if (error) *error = @"Use a letter, digit, arrow, Space, or F1 through F12.";
    return nil;
  }
  NSMutableString *label = [NSMutableString string];
  if (bits & 1) [label appendString:@"⌃"];
  if (bits & 2) [label appendString:@"⌥"];
  if (bits & 4) [label appendString:@"⇧"];
  if (bits & 8) [label appendString:@"⌘"];
  [label appendString:name];
  return @{@"keyCode": @(key), @"modifiers": @(bits), @"label": label};
}

static NSDictionary *StintShortcutConfiguration(id value, NSString **error) {
  if (![value isKindOfClass:NSDictionary.class] ||
      ![value[@"global"] isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)value[@"global"]) != CFBooleanGetTypeID() ||
      ![value[@"bindings"] isKindOfClass:NSDictionary.class]) {
    if (error) *error = @"Shortcut settings must include a scope and all four actions.";
    return nil;
  }
  NSDictionary *source = value[@"bindings"];
  if (![[NSSet setWithArray:source.allKeys] isEqualToSet:[NSSet setWithArray:StintShortcutActions()]]) {
    if (error) *error = @"Shortcut settings must include exactly Start/Pause, Reset, Skip, and Show timer panel.";
    return nil;
  }
  NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
  NSMutableDictionary *owners = [NSMutableDictionary dictionary];
  for (NSString *action in StintShortcutActions()) {
    id binding = source[action];
    if (binding == NSNull.null) {
      bindings[action] = NSNull.null;
      continue;
    }
    NSDictionary *canonical = StintShortcutBinding(binding, error);
    if (!canonical) return nil;
    NSString *identity = [NSString stringWithFormat:@"%@:%@", canonical[@"keyCode"], canonical[@"modifiers"]];
    NSString *owner = owners[identity];
    if (owner) {
      if (error) *error = [NSString stringWithFormat:@"%@ and %@ use the same shortcut. Choose a different combination.",
                          StintShortcutActionName(owner), StintShortcutActionName(action)];
      return nil;
    }
    owners[identity] = action;
    bindings[action] = canonical;
  }
  return @{@"global": @([value[@"global"] boolValue]), @"bindings": bindings};
}

static NSDictionary *StintShortcutDefaults(void) {
  NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
  NSArray *keys = @[@35, @15, @45, @1];
  [StintShortcutActions() enumerateObjectsUsingBlock:^(NSString *action, NSUInteger index, BOOL *stop) {
    (void)stop;
    bindings[action] = StintShortcutBinding(@{@"keyCode": keys[index], @"modifiers": @11}, NULL);
  }];
  return @{@"global": @YES, @"bindings": bindings};
}

@interface StintKeymap ()
@property(nonatomic, strong) NSUserDefaults *defaults;
@property(nonatomic, copy) void (^action)(NSString *);
@property(nonatomic, copy) NSDictionary *configuration;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *hotKeys;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *hotKeyActions;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *pressedHotKeys;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *pressedLocalKeys;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *suppressedKeyCodes;
@property(nonatomic) UInt32 nextIdentifier;
@property(nonatomic) EventHandlerRef eventHandler;
@property(nonatomic, strong) id localMonitor;
@property(nonatomic, strong) id resignObserver;
@property(nonatomic, copy) FlutterResult recordingResult;
@property(nonatomic) BOOL invalidated;
- (void)handleHotKeyIdentifier:(UInt32)identifier pressed:(BOOL)pressed;
- (NSEvent *)handleLocalEvent:(NSEvent *)event;
@end

static OSStatus StintShortcutEventHandler(EventHandlerCallRef next, EventRef event, void *context) {
  (void)next;
  EventHotKeyID identifier;
  OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                     NULL, sizeof(identifier), NULL, &identifier);
  if (status != noErr || identifier.signature != StintKeymapSignature) return eventNotHandledErr;
  StintKeymap *keymap = (__bridge StintKeymap *)context;
  [keymap handleHotKeyIdentifier:identifier.id pressed:GetEventKind(event) == kEventHotKeyPressed];
  return noErr;
}

@implementation StintKeymap

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults action:(void (^)(NSString *))action {
  if ((self = [super init])) {
    _defaults = defaults;
    _action = [action copy];
    _hotKeys = [NSMutableDictionary dictionary];
    _hotKeyActions = [NSMutableDictionary dictionary];
    _pressedHotKeys = [NSMutableSet set];
    _pressedLocalKeys = [NSMutableSet set];
    _suppressedKeyCodes = [NSMutableSet set];
    _nextIdentifier = 1;
    NSDictionary *stored = [defaults objectForKey:StintKeymapPreference];
    NSString *error;
    if (stored) {
      // UserDefaults property lists cannot contain null. Missing saved actions
      // represent disabled bindings, while channel settings always contain null.
      id candidate = stored;
      if ([stored isKindOfClass:NSDictionary.class] && [stored[@"bindings"] isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *bindings = [stored[@"bindings"] mutableCopy];
        for (NSString *actionKey in StintShortcutActions()) if (!bindings[actionKey]) bindings[actionKey] = NSNull.null;
        NSMutableDictionary *expanded = [stored mutableCopy];
        expanded[@"bindings"] = bindings;
        candidate = expanded;
      }
      _configuration = StintShortcutConfiguration(candidate, &error);
      if (!_configuration) _lastError = [@"Saved shortcuts could not be read. Defaults are shown. " stringByAppendingString:error];
    }
    if (!_configuration) _configuration = StintShortcutDefaults();
    _localMonitor = [self installLocalMonitor];
    if (!_localMonitor) {
      _lastError = @"Stint could not listen for shortcuts. Relaunch Stint and try again.";
    } else if (![self registerConfiguration:_configuration error:&error]) {
      _lastError = _lastError ? [_lastError stringByAppendingFormat:@" %@", error] : error;
    }
    __weak StintKeymap *weakSelf = self;
    _resignObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidResignActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
      (void)notification;
      [weakSelf applicationResigned];
    }];
  }
  return self;
}

- (id)installLocalMonitor {
  __weak StintKeymap *weakSelf = self;
  return [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp
      handler:^NSEvent *(NSEvent *event) { return [weakSelf handleLocalEvent:event] ?: (weakSelf ? nil : event); }];
}

- (void)removeLocalMonitor:(id)monitor { [NSEvent removeMonitor:monitor]; }

- (OSStatus)installHotKeyHandler {
  if (self.eventHandler) return noErr;
  EventTypeSpec events[] = {{kEventClassKeyboard, kEventHotKeyPressed}, {kEventClassKeyboard, kEventHotKeyReleased}};
  EventHandlerRef handler = NULL;
  OSStatus status = InstallEventHandler(GetApplicationEventTarget(), StintShortcutEventHandler,
      2, events, (__bridge void *)self, &handler);
  self.eventHandler = handler;
  return status;
}

- (OSStatus)registerKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers
                identifier:(UInt32)identifier reference:(EventHotKeyRef *)reference {
  EventHotKeyID hotKeyID = {StintKeymapSignature, identifier};
  return RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(),
                            kEventHotKeyExclusive, reference);
}

- (void)unregisterReference:(EventHotKeyRef)reference { UnregisterEventHotKey(reference); }

- (void)unregisterHotKeys {
  for (NSValue *reference in self.hotKeys.allValues) [self unregisterReference:reference.pointerValue];
  [self.hotKeys removeAllObjects];
  [self.hotKeyActions removeAllObjects];
  [self.pressedHotKeys removeAllObjects];
  [self.pressedLocalKeys removeAllObjects];
}

- (BOOL)registerConfiguration:(NSDictionary *)configuration error:(NSString **)error {
  if (![configuration[@"global"] boolValue]) return YES;
  BOOL hasBinding = NO;
  for (id binding in [configuration[@"bindings"] allValues]) if (binding != NSNull.null) hasBinding = YES;
  if (!hasBinding) return YES;
  OSStatus handlerStatus = [self installHotKeyHandler];
  if (handlerStatus != noErr) {
    if (error) *error = [NSString stringWithFormat:@"macOS could not enable global shortcuts (error %d). Try Only in Stint or relaunch Stint.", (int)handlerStatus];
    return NO;
  }
  for (NSString *action in StintShortcutActions()) {
    id binding = configuration[@"bindings"][action];
    if (binding == NSNull.null) continue;
    EventHotKeyRef reference = NULL;
    UInt32 identifier = self.nextIdentifier++;
    OSStatus status = [self registerKeyCode:[binding[@"keyCode"] unsignedIntValue]
        modifiers:StintShortcutCarbonModifiers([binding[@"modifiers"] unsignedIntegerValue])
        identifier:identifier reference:&reference];
    if (status != noErr || !reference) {
      if (error) *error = [NSString stringWithFormat:@"%@ (%@) could not be registered. Another app or macOS may be using it (error %d). Choose another shortcut.",
                          StintShortcutActionName(action), binding[@"label"], (int)status];
      [self unregisterHotKeys];
      return NO;
    }
    self.hotKeys[@(identifier)] = [NSValue valueWithPointer:reference];
    self.hotKeyActions[@(identifier)] = action;
  }
  return YES;
}

- (NSDictionary *)state {
  NSMutableDictionary *state = [self.configuration mutableCopy];
  state[@"defaults"] = StintShortcutDefaults();
  if (self.lastError) state[@"error"] = self.lastError;
  return state;
}

- (FlutterError *)failure:(NSString *)message {
  return [FlutterError errorWithCode:@"shortcut_error" message:message details:nil];
}

- (BOOL)saveConfiguration:(id)value error:(NSString **)error {
  NSDictionary *next = StintShortcutConfiguration(value, error);
  if (!next) return NO;
  if (!self.localMonitor) {
    if (error) *error = @"Stint could not listen for shortcuts. Relaunch Stint and try again.";
    return NO;
  }
  [self unregisterHotKeys];
  NSString *registrationError;
  if (![self registerConfiguration:next error:&registrationError]) {
    NSString *restoreError;
    BOOL restored = [self registerConfiguration:self.configuration error:&restoreError];
    self.lastError = restored ? registrationError : [registrationError stringByAppendingFormat:
        @" Previous shortcuts also could not be restored: %@ Your saved settings were kept. Try saving again or relaunch Stint.", restoreError];
    if (error) *error = self.lastError;
    return NO;
  }
  self.configuration = next;
  self.lastError = nil;
  NSMutableDictionary *savedBindings = [next[@"bindings"] mutableCopy];
  for (NSString *action in StintShortcutActions()) if (savedBindings[action] == NSNull.null) [savedBindings removeObjectForKey:action];
  [self.defaults setObject:@{@"global": next[@"global"], @"bindings": savedBindings} forKey:StintKeymapPreference];
  return YES;
}

- (NSString *)finishRecording:(id)value {
  FlutterResult result = self.recordingResult;
  if (!result) return nil;
  self.recordingResult = nil;
  [self.pressedLocalKeys removeAllObjects];
  NSString *restoreError;
  if (!self.invalidated && ![self registerConfiguration:self.configuration error:&restoreError]) {
    self.lastError = [@"Shortcuts could not be restored after recording: " stringByAppendingString:restoreError];
    result([self failure:self.lastError]);
    return self.lastError;
  } else {
    result(value);
  }
  return nil;
}

- (void)applicationResigned {
  [self.pressedLocalKeys removeAllObjects];
  [self finishRecording:nil];
  // Local key-up events may occur in the new app. Only keep suppressions for
  // registered global chords, whose Carbon release event still reaches us.
  NSMutableSet *globalKeys = [NSMutableSet set];
  for (NSString *action in self.hotKeyActions.allValues) {
    id binding = self.configuration[@"bindings"][action];
    if (binding != NSNull.null) [globalKeys addObject:binding[@"keyCode"]];
  }
  [self.suppressedKeyCodes intersectSet:globalKeys];
}

- (void)handleHotKeyIdentifier:(UInt32)identifier pressed:(BOOL)pressed {
  if (self.invalidated || self.recordingResult) return;
  NSNumber *key = @(identifier);
  NSString *action = self.hotKeyActions[key];
  if (!action) return;
  NSNumber *keyCode = self.configuration[@"bindings"][action][@"keyCode"];
  if (!pressed) {
    [self.pressedHotKeys removeObject:key];
    [self.suppressedKeyCodes removeObject:keyCode];
    return;
  }
  if ([self.suppressedKeyCodes containsObject:keyCode]) return;
  if ([self.pressedHotKeys containsObject:key]) return;
  [self.pressedHotKeys addObject:key];
  if (self.action) self.action(action);
}

- (NSEvent *)handleLocalEvent:(NSEvent *)event {
  if (self.invalidated) return event;
  NSNumber *key = @(event.keyCode);
  if (self.recordingResult) {
    if (event.type != NSEventTypeKeyDown || event.isARepeat) return nil;
    if (event.keyCode == kVK_Escape) { [self finishRecording:nil]; return nil; }
    NSString *error;
    NSDictionary *binding = StintShortcutBinding(@{@"keyCode": key,
        @"modifiers": @(StintShortcutModifiers(event.modifierFlags))}, &error);
    // Restoring a captured chord while its keys are still held must not turn
    // the recording press (or its repeat events) into a timer command.
    [self.suppressedKeyCodes addObject:key];
    [self finishRecording:binding ?: [self failure:error]];
    return nil;
  }
  if (event.type == NSEventTypeKeyUp) {
    BOOL handled = [self.pressedLocalKeys containsObject:key] || [self.suppressedKeyCodes containsObject:key];
    [self.pressedLocalKeys removeObject:key];
    [self.suppressedKeyCodes removeObject:key];
    return handled ? nil : event;
  }
  if ([self.suppressedKeyCodes containsObject:key]) {
    if (event.isARepeat) return nil;
    // A fresh press proves the captured key was released, even if its key-up
    // went to another application before Stint became active again.
    [self.suppressedKeyCodes removeObject:key];
  }
  if ([self.configuration[@"global"] boolValue]) return event;
  NSUInteger modifiers = StintShortcutModifiers(event.modifierFlags);
  for (NSString *action in StintShortcutActions()) {
    id binding = self.configuration[@"bindings"][action];
    if (binding == NSNull.null || [binding[@"keyCode"] unsignedIntegerValue] != event.keyCode ||
        [binding[@"modifiers"] unsignedIntegerValue] != modifiers) continue;
    if (!event.isARepeat && ![self.pressedLocalKeys containsObject:key]) {
      [self.pressedLocalKeys addObject:key];
      if (self.action) self.action(action);
    }
    return nil;
  }
  return event;
}

- (BOOL)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSSet *methods = [NSSet setWithArray:@[@"getShortcutSettings", @"setShortcutSettings",
                                       @"recordShortcut", @"cancelShortcutRecording"]];
  if (![methods containsObject:call.method]) return NO;
  if (self.invalidated) { result([self failure:@"Stint shortcuts are no longer available. Reopen Settings."]); return YES; }
  if ([call.method isEqualToString:@"getShortcutSettings"]) result([self state]);
  else if ([call.method isEqualToString:@"setShortcutSettings"]) {
    if (self.recordingResult) { result([self failure:@"Finish or cancel recording before saving shortcuts."]); return YES; }
    NSString *error;
    result([self saveConfiguration:call.arguments error:&error] ? [self state] : [self failure:error]);
  } else if ([call.method isEqualToString:@"cancelShortcutRecording"]) {
    NSString *error = [self finishRecording:nil];
    result(error ? [self failure:error] : nil);
  } else {
    if (self.recordingResult) { result([self failure:@"A shortcut is already being recorded."]); return YES; }
    if (!self.localMonitor) { result([self failure:@"Shortcut recording is unavailable. Relaunch Stint and try again."]); return YES; }
    [self unregisterHotKeys];
    self.recordingResult = result;
  }
  return YES;
}

- (void)invalidate {
  if (self.invalidated) return;
  self.invalidated = YES;
  [self finishRecording:nil];
  [self unregisterHotKeys];
  if (self.localMonitor) [self removeLocalMonitor:self.localMonitor];
  self.localMonitor = nil;
  if (self.eventHandler) RemoveEventHandler(self.eventHandler);
  self.eventHandler = NULL;
  if (self.resignObserver) [NSNotificationCenter.defaultCenter removeObserver:self.resignObserver];
  self.resignObserver = nil;
  self.action = nil;
}

- (void)dealloc { [self invalidate]; }
@end
