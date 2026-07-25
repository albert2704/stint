#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import "../macos/ProxyBlocker/StintProxyPreferences.h"

static NSUInteger checks;
static void Expect(BOOL condition, NSString *message) {
  checks++;
  if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSError *Failure(void) { return [NSError errorWithDomain:@"Fake" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Injected failure"}]; }
static id CopyPlist(id object) {
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:object format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
}
static NSMutableDictionary *Service(NSDictionary *proxies, BOOL enabled) {
  return [@{@"enabled":@(enabled), @"protocolEnabled":@YES, @"proxies":[proxies mutableCopy]} mutableCopy];
}
static NSDictionary *Installed(void) {
  return @{@"HTTPEnable":@1, @"HTTPProxy":@"127.0.0.1", @"HTTPPort":@48197,
           @"HTTPSEnable":@1, @"HTTPSProxy":@"127.0.0.1", @"HTTPSPort":@48197};
}

@interface FakeBackend : NSObject <StintProxyPreferencesBackend>
@property(nonatomic) NSMutableDictionary *current;
@property(nonatomic) NSMutableDictionary *staged;
@property(nonatomic) NSMutableArray *events;
@property(nonatomic) BOOL locked;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSUInteger commitFailures;
@property(nonatomic) NSUInteger applyFailures;
@property(nonatomic) NSUInteger setFailures;
@property(nonatomic) BOOL commitOnFailure;
@end
@implementation FakeBackend
- (instancetype)init {
  if ((self = [super init])) { _current = [@{@"wifi":Service(@{}, YES)} mutableCopy]; _events = [NSMutableArray array]; }
  return self;
}
- (BOOL)lock:(NSError **)error {
  [_events addObject:@"lock"];
  if (_busy) { if (error) *error = Failure(); return NO; }
  Expect(!_locked, @"backend lock is never recursive"); _locked = YES; return YES;
}
- (void)unlock { Expect(_locked, @"only acquired lock is released"); [_events addObject:@"unlock"]; _locked = NO; }
- (void)synchronize { Expect(_locked, @"synchronize follows lock"); [_events addObject:@"sync"]; _staged = CopyPlist(_current); }
- (NSDictionary *)services:(NSError **)error { (void)error; Expect(_locked, @"enumeration is locked"); return _staged; }
- (BOOL)setProxies:(NSDictionary *)proxies forService:(NSString *)service error:(NSError **)error {
  Expect(_locked, @"mutation is locked"); [_events addObject:@"set"];
  if (_setFailures) { _setFailures--; if (error) *error = Failure(); return NO; }
  _staged[service][@"proxies"] = CopyPlist(proxies); return YES;
}
- (BOOL)commit:(NSError **)error {
  Expect(_locked, @"commit is locked"); [_events addObject:@"commit"];
  if (_commitFailures) { _commitFailures--; if (_commitOnFailure) _current = CopyPlist(_staged); if (error) *error = Failure(); return NO; }
  _current = CopyPlist(_staged); return YES;
}
- (BOOL)apply:(NSError **)error {
  Expect(_locked, @"apply is locked"); [_events addObject:@"apply"];
  if (_applyFailures) { _applyFailures--; if (error) *error = Failure(); return NO; } return YES;
}
@end

@interface FakeJournal : NSObject <StintProxyJournal>
@property(nonatomic) NSDictionary *content;
@property(nonatomic) NSMutableArray *events;
@property(nonatomic) BOOL failRead;
@property(nonatomic) BOOL failWrite;
@property(nonatomic) BOOL persistOnFailure;
@property(nonatomic) BOOL failRemove;
@end
@implementation FakeJournal
- (NSDictionary *)read:(NSError **)error {
  [_events addObject:@"journal.read"];
  if (_failRead) { if (error) *error = Failure(); return nil; }
  return _content ? CopyPlist(_content) : nil;
}
- (BOOL)write:(NSDictionary *)journal error:(NSError **)error {
  [_events addObject:@"journal.write"];
  Expect(!_content, @"recovery evidence is never overwritten");
  if (!_failWrite || _persistOnFailure) _content = CopyPlist(journal);
  if (_failWrite) { if (error) *error = Failure(); return NO; } return YES;
}
- (BOOL)remove:(NSError **)error {
  [_events addObject:@"journal.remove"];
  if (_failRemove) { if (error) *error = Failure(); return NO; } _content = nil; return YES;
}
@end

static StintProxyPreferences *Router(FakeBackend **backend, FakeJournal **journal) {
  *backend = [FakeBackend new]; *journal = [FakeJournal new]; (*journal).events = (*backend).events;
  return [[StintProxyPreferences alloc] initWithBackend:*backend journal:*journal];
}
static void Activate(StintProxyPreferences *router) {
  NSError *error = nil;
  Expect([router activateForDomains:@[@"example.com"] error:&error] && router.active && !error, @"fake activation succeeds");
}
static void Restore(StintProxyPreferences *router) {
  NSError *error = nil;
  Expect([router restore:&error] && !router.active && !error, @"fake restoration succeeds");
}

static void TestRoundTrip(void) {
  FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
  NSDictionary *original = @{@"HTTPEnable":@0, @"HTTPProxy":@"old.disabled.example", @"HTTPPort":@8080,
    @"HTTPSEnable":@NO, @"ExceptionsList":@[@"*.local", @"169.254/16"], @"ExcludeSimpleHostnames":@1, @"FTPPassive":@YES};
  backend.current[@"wifi"] = Service(original, YES);
  backend.current[@"ethernet"] = Service(@{@"Unrelated":@"kept"}, YES);
  backend.current[@"disabled"] = Service(@{@"HTTPEnable":@1, @"HTTPProxy":@"corporate.example", @"HTTPPort":@8080}, NO);
  NSDictionary *before = CopyPlist(backend.current);
  Activate(router);
  Expect(journal.content != nil, @"journal remains throughout active routing");
  Expect([journal.content[@"services"] count] == 2, @"disabled service excluded from journal");
  Expect([journal.content[@"services"][@"wifi"][@"missing"] containsObject:@"HTTPSProxy"], @"missing original represented separately");
  Expect([backend.current[@"wifi"][@"proxies"][@"ExcludeSimpleHostnames"] isEqual:@1], @"unrelated keys preserved");
  Expect([backend.current[@"wifi"][@"proxies"][@"HTTPPort"] isEqual:@48197], @"fixed production port selected");
  Expect([backend.current[@"disabled"] isEqual:before[@"disabled"]], @"disabled service untouched");
  NSArray *events = backend.events;
  Expect([events indexOfObject:@"journal.write"] < [events indexOfObject:@"set"], @"journal precedes first preference mutation");
  Expect([events indexOfObject:@"set"] < [events indexOfObject:@"commit"] && [events indexOfObject:@"commit"] < [events indexOfObject:@"apply"], @"commit and apply follow staging");
  NSUInteger priorSets = [[events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'set'"]] count];
  Activate(router);
  Expect([[backend.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'set'"]] count] == priorSets, @"active activation does not rewrite preferences");
  Restore(router);
  Expect([backend.current isEqual:before], @"exact original values and missing keys restored");
  Expect(!journal.content, @"journal removed only after successful restore");
  Expect([backend.events.lastObject isEqual:@"journal.remove"], @"journal removal follows commit apply and unlock");
  NSUInteger operations = backend.events.count;
  Restore(router);
  Expect(backend.events.count == operations + 1, @"no journal restoration is a read-only no-op");
}

static void TestConflicts(void) {
  for (NSString *key in @[@"HTTPEnable", @"HTTPSEnable", @"SOCKSEnable", @"ProxyAutoConfigEnable", @"ProxyAutoDiscoveryEnable"]) {
    FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
    backend.current[@"other-service"] = Service(@{key:@1}, YES);
    NSError *error = nil;
    Expect(![router activateForDomains:@[@"example.com"] error:&error] && error && !router.active, [@"existing enabled proxy refused: " stringByAppendingString:key]);
    Expect(!journal.content && ![backend.events containsObject:@"set"], @"conflict anywhere refuses every mutation");
  }
  for (id exceptions in @[@[@"*.example.com"], @[@"<local>"], @[@7], @"bad"]) {
    FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
    backend.current[@"wifi"] = Service(@{@"ExceptionsList":exceptions}, YES);
    NSError *error = nil;
    Expect(![router activateForDomains:@[@"example.com"] error:&error] && error, @"unsupported proxy exception refused");
    Expect(!journal.content && ![backend.events containsObject:@"set"], @"exception refusal changes no preferences");
  }
  FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
  backend.current[@"wifi"] = Service(@{@"ExceptionsList":@[@"*.local"]}, YES);
  Activate(router);
  NSError *error = nil;
  Expect(![router activateForDomains:@[@"example.com", @"printer.local"] error:&error] && error && !router.active, @"domain update rechecks default local exception");
  Expect(!journal.content && !backend.current[@"wifi"][@"proxies"][@"HTTPEnable"], @"exception drift restores routing");
  router = Router(&backend, &journal); backend.current[@"wifi"][@"enabled"] = @NO;
  error = nil; Expect(![router activateForDomains:@[@"example.com"] error:&error] && error, @"no eligible services refused");
  router = Router(&backend, &journal); backend.current[@"wifi"][@"protocolEnabled"] = @NO;
  error = nil; Expect(![router activateForDomains:@[@"example.com"] error:&error] && error, @"disabled proxy protocol refused");
}

static void TestFailures(void) {
  FakeBackend *backend; FakeJournal *journal; NSError *error = nil;
  StintProxyPreferences *router = Router(&backend, &journal); backend.busy = YES;
  Expect(![router activateForDomains:@[@"example.com"] error:&error] && error, @"nonblocking busy preferences fail");
  Expect(![backend.events containsObject:@"set"] && !journal.content, @"busy lock changes nothing");
  for (NSNumber *persist in @[@NO, @YES]) {
    router = Router(&backend, &journal); journal.failWrite = YES; journal.persistOnFailure = persist.boolValue; error = nil;
    Expect(![router activateForDomains:@[@"example.com"] error:&error] && error && !router.active, @"journal failure never reports active");
    Expect(![backend.events containsObject:@"set"], @"journal failure precedes all setting mutations");
    Expect(!journal.content, @"post-rename journal failure is recovered");
  }
  for (NSString *failure in @[@"set", @"commit", @"uncertainCommit", @"apply"]) {
    router = Router(&backend, &journal);
    if ([failure isEqual:@"set"]) backend.setFailures = 1;
    if ([failure containsString:@"Commit"] || [failure isEqual:@"commit"]) backend.commitFailures = 1;
    backend.commitOnFailure = [failure isEqual:@"uncertainCommit"];
    if ([failure isEqual:@"apply"]) backend.applyFailures = 1;
    error = nil;
    Expect(![router activateForDomains:@[@"example.com"] error:&error] && error && !router.active, [@"activation failure reported: " stringByAppendingString:failure]);
    Expect(!journal.content && [backend.current[@"wifi"][@"proxies"] count] == 0, @"failed activation automatically restores exact original");
  }
  router = Router(&backend, &journal); Activate(router); backend.applyFailures = 1;
  error = nil; Expect(![router restore:&error] && error && !router.active, @"restore apply failure reported");
  Expect(journal.content != nil && !backend.current[@"wifi"][@"proxies"][@"HTTPEnable"], @"journal kept after originals committed but apply failed");
  NSUInteger applyCount = [[backend.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'apply'"]] count];
  Restore(router);
  Expect([[backend.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'apply'"]] count] == applyCount + 1, @"retry applies even with no remaining changed keys");
  router = Router(&backend, &journal); Activate(router); backend.commitFailures = 1;
  error = nil; Expect(![router restore:&error] && error && journal.content, @"restore commit failure retains evidence");
  Restore(router);
  router = Router(&backend, &journal); Activate(router); journal.failRemove = YES;
  error = nil; Expect(![router restore:&error] && error && journal.content, @"remove failure retains journal and reports recovery pending");
  journal.failRemove = NO; Restore(router);
  router = Router(&backend, &journal); Activate(router); journal.failRead = YES;
  error = nil; Expect(![router restore:&error] && error && journal.content, @"read failure retains evidence");
  journal.failRead = NO; Restore(router);
}

static void TestRestartAndDrift(void) {
  FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
  Activate(router);
  router = [[StintProxyPreferences alloc] initWithBackend:backend journal:journal];
  Expect(!router.active, @"restart never assumes a stale journal is active protection"); Restore(router);
  for (NSString *change in @[@"new", @"deleted", @"disabled", @"owned", @"pac", @"exception", @"journalRemoved"]) {
    router = Router(&backend, &journal); Activate(router);
    if ([change isEqual:@"new"]) backend.current[@"new-service"] = Service(@{}, YES);
    if ([change isEqual:@"deleted"]) [backend.current removeObjectForKey:@"wifi"];
    if ([change isEqual:@"disabled"]) backend.current[@"wifi"][@"enabled"] = @NO;
    if ([change isEqual:@"owned"]) backend.current[@"wifi"][@"proxies"][@"HTTPSProxy"] = @"externally.edited";
    if ([change isEqual:@"pac"]) backend.current[@"wifi"][@"proxies"][@"ProxyAutoConfigEnable"] = @1;
    if ([change isEqual:@"exception"]) backend.current[@"wifi"][@"proxies"][@"ExceptionsList"] = @[@"*.example.com"];
    if ([change isEqual:@"journalRemoved"]) journal.content = nil;
    NSError *error = nil;
    Expect(![router validateActive:&error] && error && !router.active, [@"active drift detected: " stringByAppendingString:change]);
    Expect(!journal.content, @"detected drift recovers journal");
    for (NSString *serviceID in backend.current)
      Expect(![backend.current[serviceID][@"proxies"][@"HTTPEnable"] boolValue], @"drift leaves no Stint HTTP route active");
    if ([change isEqual:@"owned"]) Expect([backend.current[@"wifi"][@"proxies"][@"HTTPSProxy"] isEqual:@"externally.edited"], @"drift recovery preserves external owned-key edit");
    if ([change isEqual:@"pac"]) Expect([backend.current[@"wifi"][@"proxies"][@"ProxyAutoConfigEnable"] isEqual:@1], @"drift recovery preserves external PAC edit");
  }
  router = Router(&backend, &journal); Activate(router);
  backend.current[@"disabled-new"] = Service(@{}, NO);
  backend.current[@"wifi"][@"proxies"][@"FTPPassive"] = @0;
  NSError *error = nil;
  Expect([router validateActive:&error] && !error, @"unrelated edits and disabled new services do not invalidate routing");
  Restore(router);
  Expect([backend.current[@"wifi"][@"proxies"][@"FTPPassive"] isEqual:@0], @"unrelated edit survives restoration");
}

static void TestPerKeyRecovery(void) {
  FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal);
  Activate(router);
  NSMutableDictionary *proxies = backend.current[@"wifi"][@"proxies"];
  proxies[@"HTTPEnable"] = @0; proxies[@"HTTPSProxy"] = @"new.proxy.example"; proxies[@"Extra"] = @"untouched";
  Restore(router);
  Expect([backend.current[@"wifi"][@"proxies"] isEqual:@{@"HTTPEnable":@0, @"HTTPSProxy":@"new.proxy.example", @"Extra":@"untouched"}], @"each owned key restored only if equal to installed");
  router = Router(&backend, &journal); Activate(router); proxies = backend.current[@"wifi"][@"proxies"];
  proxies[@"HTTPPort"] = @1234;
  Restore(router);
  Expect([backend.current[@"wifi"][@"proxies"] isEqual:@{@"HTTPPort":@1234}], @"partial port edit disables Stint and preserves edited port");
  router = Router(&backend, &journal);
  backend.current[@"wifi"] = Service(@{@"HTTPEnable":@0, @"HTTPProxy":@"127.0.0.1", @"HTTPPort":@48197}, YES);
  backend.current[@"ethernet"] = Service(@{}, YES);
  Activate(router);
  backend.current[@"wifi"][@"proxies"][@"HTTPEnable"] = @2;
  NSError *error = nil;
  Expect(![router restore:&error] && error && journal.content, @"ambiguous external enable edit retains actionable recovery evidence");
  Expect([error.localizedDescription containsString:@"System Settings"], @"ambiguous recovery gives manual action");
  Expect(!backend.current[@"ethernet"][@"proxies"][@"HTTPEnable"], @"unaffected services restore despite another ambiguous service");
  backend.current[@"wifi"][@"proxies"][@"HTTPEnable"] = @0;
  Restore(router);
  Expect([backend.current[@"wifi"][@"proxies"][@"HTTPEnable"] isEqual:@0], @"manual safe edit permits retry");
}

static void TestJournalValidation(void) {
  FakeBackend *backend; FakeJournal *journal; StintProxyPreferences *router = Router(&backend, &journal); Activate(router);
  NSDictionary *valid = CopyPlist(journal.content);
  NSMutableArray *invalid = [NSMutableArray array];
  [invalid addObject:@{@"version":@2, @"services":valid[@"services"]}];
  [invalid addObject:@{@"version":@1, @"services":@{}}];
  NSMutableDictionary *bad = CopyPlist(valid); bad[@"services"][@"wifi"][@"installed"][@"HTTPPort"] = @8080; [invalid addObject:bad];
  bad = CopyPlist(valid); [bad[@"services"][@"wifi"][@"missing"] addObject:@"HTTPEnable"]; [invalid addObject:bad];
  bad = CopyPlist(valid); [bad[@"services"][@"wifi"][@"missing"] removeObject:@"HTTPEnable"]; [invalid addObject:bad];
  bad = CopyPlist(valid); bad[@"services"][@"wifi"][@"original"][@"SOCKSEnable"] = @1; [invalid addObject:bad];
  bad = CopyPlist(valid); [bad[@"services"][@"wifi"][@"missing"] removeObject:@"HTTPEnable"]; bad[@"services"][@"wifi"][@"original"][@"HTTPEnable"] = @1; [invalid addObject:bad];
  for (NSDictionary *input in invalid) {
    journal.content = input; [backend.events removeAllObjects]; NSError *error = nil;
    Expect(![router restore:&error] && error && journal.content, @"malformed journal refused and retained");
    Expect(![backend.events containsObject:@"set"] && ![backend.events containsObject:@"commit"], @"malformed journal cannot edit settings");
  }
  journal.content = valid; Restore(router);
}

static void TestFilesystem(void) {
  // The secure adapter intentionally refuses /tmp because it is world-writable.
  // The repository and its real ancestors are verified exactly as in production.
  NSString *base = [[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"build/native-tests"] stringByAppendingPathComponent:[@"proxy-journal-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  NSError *error = nil;
  Expect([NSFileManager.defaultManager createDirectoryAtPath:base withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error], @"create isolated secure journal fixture");
  NSString *path = [base stringByAppendingPathComponent:@"recovery.plist"];
  id<StintProxyJournal> journal = StintProxyTestJournal(path, getuid());
  NSDictionary *sample = @{@"version":@1, @"services":@{@"wifi":@{@"original":@{}, @"missing":Installed().allKeys, @"installed":Installed()}}};
  error = nil; Expect(![journal read:&error] && !error, @"absent journal distinct from invalid file");
  Expect([journal write:sample error:&error] && !error, @"production journal saves binary plist");
  struct stat info; Expect(!lstat(path.fileSystemRepresentation, &info) && info.st_uid == getuid() && (info.st_mode & 07777) == 0600 && info.st_nlink == 1, @"journal has exact secure owner mode and link count");
  NSData *data = [NSData dataWithContentsOfFile:path];
  Expect(data.length >= 8 && !memcmp(data.bytes, "bplist00", 8), @"journal uses binary plist");
  Expect([[journal read:&error] isEqual:sample] && !error, @"binary journal round trip");
  error = nil; Expect(![journal write:sample error:&error] && error, @"existing evidence cannot be replaced");
  error = nil; Expect([journal remove:&error] && !error, @"secure journal removal");

  NSString *target = [base stringByAppendingPathComponent:@"target.plist"];
  Expect([data writeToFile:target atomically:NO], @"create link target fixture"); chmod(target.fileSystemRepresentation, 0600);
  Expect(!symlink(target.fileSystemRepresentation, path.fileSystemRepresentation), @"create symlink fixture");
  error = nil; Expect(![journal read:&error] && error, @"journal symlink refused");
  error = nil; Expect(![journal write:sample error:&error] && error, @"write never follows journal symlink");
  error = nil; Expect(![journal remove:&error] && error, @"unsafe journal symlink retained"); unlink(path.fileSystemRepresentation);
  Expect(!link(target.fileSystemRepresentation, path.fileSystemRepresentation), @"create hardlink fixture");
  error = nil; Expect(![journal read:&error] && error, @"journal hardlink refused"); unlink(path.fileSystemRepresentation);
  Expect([data writeToFile:path atomically:NO], @"create permissions fixture"); chmod(path.fileSystemRepresentation, 0644);
  error = nil; Expect(![journal read:&error] && error, @"journal readable by others refused"); chmod(path.fileSystemRepresentation, 0600);
  id<StintProxyJournal> wrongOwner = StintProxyTestJournal(path, getuid() + 1);
  error = nil; Expect(![wrongOwner read:&error] && error, @"wrong journal owner refused");
  unlink(path.fileSystemRepresentation);
  int fd = open(path.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
  Expect(fd >= 0 && !ftruncate(fd, 1024 * 1024 + 1), @"create oversize fixture"); close(fd);
  error = nil; Expect(![journal read:&error] && error, @"journal larger than one MiB refused"); unlink(path.fileSystemRepresentation);
  Expect(!mkfifo(path.fileSystemRepresentation, 0600), @"create FIFO fixture");
  error = nil; Expect(![journal read:&error] && error, @"FIFO refused without blocking"); unlink(path.fileSystemRepresentation);
  NSData *xml = [NSPropertyListSerialization dataWithPropertyList:sample format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
  Expect([xml writeToFile:path atomically:NO], @"create nonbinary fixture"); chmod(path.fileSystemRepresentation, 0600);
  error = nil; Expect(![journal read:&error] && error, @"nonbinary journal refused"); unlink(path.fileSystemRepresentation);
  Expect([@"corrupt" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL], @"create corrupt fixture"); chmod(path.fileSystemRepresentation, 0600);
  error = nil; Expect(![journal read:&error] && error, @"corrupt journal refused"); unlink(path.fileSystemRepresentation);
  chmod(base.fileSystemRepresentation, 0770);
  error = nil; Expect(![journal read:&error] && error, @"group-writable ancestor refused"); chmod(base.fileSystemRepresentation, 0700);
  NSString *linkDirectory = [base stringByAppendingPathComponent:@"linked-directory"];
  Expect(!symlink(base.fileSystemRepresentation, linkDirectory.fileSystemRepresentation), @"create linked ancestor fixture");
  id<StintProxyJournal> linked = StintProxyTestJournal([linkDirectory stringByAppendingPathComponent:@"recovery.plist"], getuid());
  error = nil; Expect(![linked read:&error] && error, @"symlink ancestor refused"); unlink(linkDirectory.fileSystemRepresentation);
  id<StintProxyJournal> shared = StintProxyTestJournal(@"/private/tmp/stint-proxy-should-not-exist.plist", getuid());
  error = nil; Expect(![shared read:&error] && error, @"world-writable ancestor refused");
  NSDictionary *large = @{@"payload":[@"x" stringByPaddingToLength:1024 * 1024 + 1 withString:@"x" startingAtIndex:0]};
  error = nil; Expect(![journal write:large error:&error] && error, @"oversize write refused before file creation");
  Expect(![NSFileManager.defaultManager fileExistsAtPath:path], @"invalid write leaves no recovery file");
  Expect([NSFileManager.defaultManager removeItemAtPath:base error:NULL], @"remove isolated fixtures");
}

int main(void) {
  @autoreleasepool {
    TestRoundTrip(); TestConflicts(); TestFailures(); TestRestartAndDrift(); TestPerKeyRecovery(); TestJournalValidation(); TestFilesystem();
    printf("PASS: %lu proxy preference checks (fake SystemConfiguration; no system settings changed)\n", (unsigned long)checks);
  }
  return 0;
}
