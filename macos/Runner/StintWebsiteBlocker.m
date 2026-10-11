#import "StintWebsiteBlocker.h"
#import "../HostsBlocker/StintBlockerPolicy.h"
#import "../HostsBlocker/StintHostsFile.h"
#import "../ProxyBlocker/StintLocalProxy.h"
#import <Cocoa/Cocoa.h>
#import <pwd.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

@interface StintWebsiteBlocker ()
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic) BOOL setupPending;
@property(nonatomic, copy) NSString *writeError;
@property(nonatomic, strong) StintLocalProxy *proxy;
@property(nonatomic, copy) NSString *requestedSession;
@property(nonatomic, strong) NSTimer *statusTimer;
@end
@implementation StintWebsiteBlocker
- (instancetype)init {
  if ((self = [super init])) {
    _snapshot = @{@"status": @"notInstalled", @"message": @"Set up the free website helper once with your administrator password."};
    __weak StintWebsiteBlocker *weakSelf = self;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
      [weakSelf statusWithReply:^(__unused NSDictionary *status) {}];
    }];
  }
  return self;
}
- (void)dealloc { [self.statusTimer invalidate]; [self.proxy stop]; }
- (StintLocalProxy *)makeProxy { return [[StintLocalProxy alloc] initWithPort:48197]; }
- (NSString *)policyDirectory {
  struct passwd *user = getpwuid(getuid());
  return user ? [[NSString stringWithUTF8String:user->pw_dir] stringByAppendingPathComponent:@"Library/Application Support/Stint Website Blocker"] : nil;
}
- (int)openDirectoryCreating:(BOOL)create {
  NSString *path = [self policyDirectory]; if (!path) return -1;
  if (create) [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
  // This unprivileged app may access only the named sandbox exception folder.
  // The privileged reader independently validates every ancestor and owner.
  int fd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  struct stat info;
  if (fd >= 0 && (fstat(fd, &info) || info.st_uid != getuid() || (info.st_mode & 0022))) { close(fd); return -1; }
  return fd;
}
- (void)publish:(NSString *)status message:(NSString *)message {
  [self publish:status message:message active:NO];
}
- (void)publish:(NSString *)status message:(NSString *)message active:(BOOL)active {
  NSDictionary *next = @{@"status": status, @"message": message, @"active": @(active)};
  if ([next isEqualToDictionary:self.snapshot]) return;
  self.snapshot = next;
  if (self.statusChanged) self.statusChanged(next);
}
- (void)statusWithReply:(void (^)(NSDictionary *))reply {
  if (self.writeError) { [self publish:@"unavailable" message:self.writeError]; reply(self.snapshot); return; }
  int directory = [self openDirectoryCreating:NO];
  NSData *data = directory >= 0 ? StintReadBoundedAt(directory, "helper-status.json", 0, 8192) : nil;
  if (directory >= 0) close(directory);
  id status = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  double now = NSDate.date.timeIntervalSince1970 * 1000;
  BOOL fresh = [status isKindOfClass:NSDictionary.class] &&
      [status[@"heartbeatMilliseconds"] isKindOfClass:NSNumber.class] &&
      [status[@"heartbeatMilliseconds"] doubleValue] <= now+1000 && [status[@"heartbeatMilliseconds"] doubleValue] > now-12000;
  if (fresh && [status[@"version"] isEqual:@1] &&
      [status[@"ownerUID"] isKindOfClass:NSNumber.class] && [status[@"ownerUID"] unsignedIntValue] == getuid()) {
    [self publish:self.setupPending ? @"approvalRequired" : @"notInstalled" message:self.setupPending ?
      @"Double-click the highlighted Install Website Blocker.command in Finder, finish its administrator prompts in Terminal, then choose Refresh to check the upgrade." :
      @"Update the website helper to enable the new local proxy. Choose Set up website blocker and run the highlighted command in Finder."];
    reply(self.snapshot); return;
  }
  if (fresh && [status[@"version"] isEqual:@2] && [status[@"transport"] isEqual:@"proxy"] &&
      [status[@"ownerUID"] isKindOfClass:NSNumber.class] && [status[@"ownerUID"] unsignedIntValue] == getuid() &&
      [status[@"heartbeatMilliseconds"] isKindOfClass:NSNumber.class] &&
      [status[@"heartbeatMilliseconds"] doubleValue] <= now+1000 && [status[@"heartbeatMilliseconds"] doubleValue] > now-12000 &&
      [@[@"configured", @"unavailable", @"notInstalled"] containsObject:status[@"status"]] &&
      [status[@"message"] isKindOfClass:NSString.class] && [status[@"message"] length] <= 1000) {
    self.setupPending = NO;
    [self publish:status[@"status"] message:status[@"message"] active:([status[@"active"] isEqual:@YES] && self.requestedSession.length && [self.requestedSession isEqual:status[@"sessionId"]])];
  } else {
    [self publish:self.setupPending ? @"approvalRequired" : @"notInstalled" message:self.setupPending ?
      @"Double-click the highlighted command in Finder, finish its prompts in Terminal, then choose Refresh. Enter your administrator password only in Terminal." :
      @"The website helper is not running. Set it up once with administrator approval. No Apple subscription or browser extension is needed."];
  }
  reply(self.snapshot);
}
- (void)update:(NSDictionary *)state {
  double now = NSDate.date.timeIntervalSince1970 * 1000;
  NSMutableDictionary *policy = [@{@"version":@2, @"active":@NO} mutableCopy];
  NSError *proxyError = nil;
  if (!self.proxy) self.proxy = [self makeProxy];
  BOOL proxyReady = self.proxy.running || [self.proxy start:&proxyError];
  if (proxyReady && [state[@"active"] isEqual:@YES]) {
    for (NSString *key in @[@"active", @"sessionId", @"domains", @"deadlineMilliseconds", @"leaseExpiresAt"])
      if (state[key] && state[key] != NSNull.null) policy[key] = state[key];
    policy[@"ownerUID"] = @(getuid()); policy[@"issuedAtMilliseconds"] = @(now);
    if (![[StintBlockerPolicy policyWithDictionary:policy now:now uptime:NSProcessInfo.processInfo.systemUptime] isEffectiveAt:now uptime:NSProcessInfo.processInfo.systemUptime]) policy = [@{@"version":@2, @"active":@NO} mutableCopy];
  }
  if (proxyReady) { policy[@"proxyPort"] = @(self.proxy.port); policy[@"proxyToken"] = self.proxy.token; }
  self.requestedSession = [policy[@"active"] isEqual:@YES] ? policy[@"sessionId"] : nil;
  [self.proxy updatePolicy:policy];
  int directory = [self openDirectoryCreating:YES];
  NSData *data = [NSJSONSerialization dataWithJSONObject:policy options:0 error:NULL];
  NSString *temp = [@".stint-policy-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = directory >= 0 ? openat(directory, temp.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600) : -1;
  BOOL okay = fd >= 0; NSUInteger offset = 0;
  while (okay && offset < data.length) {
    ssize_t count = write(fd, (const uint8_t *)data.bytes+offset, data.length-offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) { okay = NO; break; } offset += count;
  }
  if (okay) okay = fsync(fd) == 0;
  if (fd >= 0) close(fd);
  if (okay) okay = renameat(directory, temp.UTF8String, directory, "policy.json") == 0;
  if (!okay && directory >= 0) unlinkat(directory, temp.UTF8String, 0);
  if (directory >= 0) close(directory);
  self.writeError = !proxyReady ? (proxyError.localizedDescription ?: @"The local website proxy could not start. Quit another copy of Stint and try again.") :
    (okay ? nil : @"Could not update the website helper settings. Its last focus lease expires within 30 seconds while the helper is running. App blocking is independent.");
  [self statusWithReply:^(__unused NSDictionary *status) {}];
}
- (NSURL *)setupCommandURL:(NSString *)name {
  return [NSBundle.mainBundle URLForResource:name withExtension:@"command" subdirectory:@"WebsiteBlocker"];
}
- (void)revealSetupCommand:(NSURL *)script {
  // Sandboxed apps cannot send executable command documents to Terminal.
  // Finder reveals the file; the user explicitly opens and authorizes it.
  [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[script]];
}
- (void)openSetup:(NSString *)name reply:(void (^)(NSDictionary *))reply {
  int directory = [self openDirectoryCreating:YES];
  if (directory < 0) { [self publish:@"unavailable" message:@"Could not create the website helper settings folder. Reopen Stint and try again."]; reply(self.snapshot); return; }
  close(directory);
  NSURL *script = [self setupCommandURL:name];
  if (!script) { [self publish:@"unavailable" message:@"The setup command is missing from this build. Rebuild or reinstall Stint."]; reply(self.snapshot); return; }
  self.setupPending = YES;
  [self revealSetupCommand:script];
  [self publish:@"approvalRequired" message:[NSString stringWithFormat:@"In Finder, double-click “%@.command”. Complete its prompts in Terminal, then return here and choose Refresh. Enter your administrator password only in Terminal.", name]];
  reply(self.snapshot);
}
- (void)enableWithReply:(void (^)(NSDictionary *))reply { [self openSetup:@"Install Website Blocker" reply:reply]; }
- (void)removeWithReply:(void (^)(NSDictionary *))reply { [self openSetup:@"Remove Website Blocker" reply:reply]; }
@end
