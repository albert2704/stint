#define STINT_PROXY_INTERNAL 1
#import "StintProxyPreferences.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static const NSUInteger StintJournalLimit = 1024 * 1024;
static const NSUInteger StintServiceLimit = 256;

static NSError *StintProxyError(NSString *message) {
  return [NSError errorWithDomain:@"StintProxyPreferences" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL StintProxyFail(NSError **error, NSString *message) {
  if (error) *error = StintProxyError(message);
  return NO;
}
static NSArray<NSString *> *StintOwnedKeys(void) {
  return @[@"HTTPEnable", @"HTTPProxy", @"HTTPPort", @"HTTPSEnable", @"HTTPSProxy", @"HTTPSPort"];
}
static NSDictionary *StintInstalledValues(void) {
  return @{@"HTTPEnable":@1, @"HTTPProxy":@"127.0.0.1", @"HTTPPort":@48197,
           @"HTTPSEnable":@1, @"HTTPSProxy":@"127.0.0.1", @"HTTPSPort":@48197};
}
static BOOL StintEqual(id a, id b) { return a == b || [a isEqual:b]; }

@interface StintSCProxyBackend : NSObject <StintProxyPreferencesBackend> {
  SCPreferencesRef _preferences;
  NSMutableDictionary *_protocols;
  BOOL _locked;
}
@end

@implementation StintSCProxyBackend
- (instancetype)init {
  if ((self = [super init])) _preferences = SCPreferencesCreate(NULL, CFSTR("Stint Proxy Recovery"), NULL);
  return self;
}
- (void)dealloc { [self unlock]; if (_preferences) CFRelease(_preferences); }
- (BOOL)lock:(NSError **)error {
  // SCPreferencesLock may reject a stale session before acquiring its lock.
  // Discard any old cache/staged failure first; callers also synchronize under
  // the acquired lock so snapshots always reflect the current committed state.
  if (_preferences) SCPreferencesSynchronize(_preferences);
  if (!_preferences || !SCPreferencesLock(_preferences, false))
    return StintProxyFail(error, @"Network preferences are busy or unavailable. Stint will retry recovery.");
  _locked = YES;
  return YES;
}
- (void)unlock { if (_locked) { SCPreferencesUnlock(_preferences); _locked = NO; } }
- (void)synchronize { if (_preferences) SCPreferencesSynchronize(_preferences); }
- (NSDictionary *)services:(NSError **)error {
  NSArray *services = CFBridgingRelease(SCNetworkServiceCopyAll(_preferences));
  if (!services || services.count > StintServiceLimit) {
    StintProxyFail(error, @"Cannot enumerate network services safely."); return nil;
  }
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  _protocols = [NSMutableDictionary dictionary];
  for (id object in services) {
    SCNetworkServiceRef service = (__bridge SCNetworkServiceRef)object;
    NSString *serviceID = (__bridge NSString *)SCNetworkServiceGetServiceID(service);
    SCNetworkProtocolRef protocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies);
    if (!protocol) continue;
    NSDictionary *configuration = (__bridge NSDictionary *)SCNetworkProtocolGetConfiguration(protocol);
    if (!serviceID || (configuration && ![configuration isKindOfClass:NSDictionary.class])) {
      CFRelease(protocol); StintProxyFail(error, @"A network service has invalid proxy preferences."); return nil;
    }
    result[serviceID] = @{@"enabled":@(SCNetworkServiceGetEnabled(service)),
                          @"protocolEnabled":@(SCNetworkProtocolGetEnabled(protocol)),
                          @"proxies":configuration ?: @{}};
    _protocols[serviceID] = CFBridgingRelease(protocol);
  }
  return result;
}
- (BOOL)setProxies:(NSDictionary *)proxies forService:(NSString *)service error:(NSError **)error {
  SCNetworkProtocolRef protocol = (__bridge SCNetworkProtocolRef)_protocols[service];
  return (protocol && SCNetworkProtocolSetConfiguration(protocol, (__bridge CFDictionaryRef)proxies)) ||
    StintProxyFail(error, @"Could not stage network proxy settings. Recovery will be retried.");
}
- (BOOL)commit:(NSError **)error {
  return SCPreferencesCommitChanges(_preferences) || StintProxyFail(error, @"Could not commit network proxy settings. Recovery will be retried.");
}
- (BOOL)apply:(NSError **)error {
  return SCPreferencesApplyChanges(_preferences) || StintProxyFail(error, @"Could not apply network proxy settings. Recovery will be retried.");
}
@end

/// Every ancestor is opened relative to an already verified directory descriptor.
/// No symlink, writable ancestor, cross-owner directory or linked journal is trusted.
static int StintJournalDirectory(NSString *path, uid_t owner) {
  if (![path hasPrefix:@"/"] || !path.lastPathComponent.length) return -1;
  int directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (directory < 0) return -1;
  NSArray *components = path.stringByDeletingLastPathComponent.pathComponents;
  for (NSString *component in components) {
    if ([component isEqual:@"/"]) continue;
    if ([component isEqual:@"."] || [component isEqual:@".."] || !component.length) { close(directory); return -1; }
    int next = openat(directory, component.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(directory); directory = next;
    struct stat info;
    if (directory < 0) return -1;
    if (fstat(directory, &info) || !S_ISDIR(info.st_mode) ||
        (info.st_uid != 0 && info.st_uid != owner) || (info.st_mode & 0022)) {
      close(directory); return -1;
    }
  }
  struct stat info;
  if (fstat(directory, &info) || info.st_uid != owner ||
      [path.lastPathComponent isEqual:@"."] || [path.lastPathComponent isEqual:@".."]) {
    close(directory); return -1;
  }
  return directory;
}
static BOOL StintSecureJournal(struct stat info, uid_t owner) {
  return S_ISREG(info.st_mode) && info.st_uid == owner && info.st_nlink == 1 &&
    (info.st_mode & 07777) == 0600 && info.st_size >= 0 && (uint64_t)info.st_size <= StintJournalLimit;
}
static NSData *StintJournalReadFD(int fd) {
  NSMutableData *result = [NSMutableData data]; uint8_t bytes[4096];
  for (;;) {
    ssize_t count = read(fd, bytes, sizeof(bytes));
    if (count < 0 && errno == EINTR) continue;
    if (count < 0 || (count > 0 && result.length + (NSUInteger)count > StintJournalLimit)) return nil;
    if (!count) return result;
    [result appendBytes:bytes length:(NSUInteger)count];
  }
}

@interface StintFileProxyJournal : NSObject <StintProxyJournal>
@property(nonatomic, copy) NSString *path;
@property(nonatomic) uid_t owner;
@end
@implementation StintFileProxyJournal
- (NSDictionary *)read:(NSError **)error {
  if (error) *error = nil;
  int directory = StintJournalDirectory(_path, _owner);
  if (directory < 0) { StintProxyFail(error, @"The proxy recovery directory is unsafe or unavailable. Repair the Stint helper installation."); return nil; }
  int fd = openat(directory, _path.lastPathComponent.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  int failure = errno; close(directory);
  if (fd < 0) {
    if (failure != ENOENT) StintProxyFail(error, @"The proxy recovery journal cannot be safely opened. See the manual proxy recovery guide.");
    return nil;
  }
  struct stat info; NSData *data = nil;
  if (!fstat(fd, &info) && StintSecureJournal(info, _owner)) data = StintJournalReadFD(fd);
  close(fd);
  NSPropertyListFormat format = 0;
  id journal = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:&format error:NULL] : nil;
  if (![journal isKindOfClass:NSDictionary.class] || format != NSPropertyListBinaryFormat_v1_0) {
    StintProxyFail(error, @"The proxy recovery journal is unsafe or invalid. Keep it for manual recovery; Stint did not overwrite it."); return nil;
  }
  return journal;
}
- (BOOL)write:(NSDictionary *)journal error:(NSError **)error {
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:journal format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  if (!data || data.length > StintJournalLimit) return StintProxyFail(error, @"The proxy recovery snapshot is invalid or too large.");
  int directory = StintJournalDirectory(_path, _owner);
  if (directory < 0) return StintProxyFail(error, @"The proxy recovery directory is unsafe or unavailable. Repair the Stint helper installation.");
  // Never replace existing recovery evidence, even if the caller missed a restart.
  struct stat previous;
  BOOL absent = fstatat(directory, _path.lastPathComponent.fileSystemRepresentation, &previous, AT_SYMLINK_NOFOLLOW) < 0 && errno == ENOENT;
  if (!absent) { close(directory); return StintProxyFail(error, @"A proxy recovery journal already exists. Restore it before activating protection."); }
  NSString *temporary = [@".stint-proxy-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = openat(directory, temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  BOOL okay = fd >= 0;
  if (okay) {
    struct stat info;
    okay = !fstat(fd, &info) && info.st_uid == _owner && !fchmod(fd, 0600);
    NSUInteger offset = 0;
    while (okay && offset < data.length) {
      ssize_t count = write(fd, (const uint8_t *)data.bytes + offset, data.length - offset);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0) okay = NO; else offset += (NSUInteger)count;
    }
    if (okay) okay = fsync(fd) == 0;
    close(fd);
  }
  // Exclusive rename also prevents replacement by a second writer.
  if (okay) okay = renameatx_np(directory, temporary.fileSystemRepresentation, directory,
                                _path.lastPathComponent.fileSystemRepresentation, RENAME_EXCL) == 0;
  if (okay) okay = fsync(directory) == 0;
  (void)unlinkat(directory, temporary.fileSystemRepresentation, 0);
  close(directory);
  return okay || StintProxyFail(error, @"Could not durably save proxy recovery settings. Stint did not activate routing.");
}
- (BOOL)remove:(NSError **)error {
  int directory = StintJournalDirectory(_path, _owner);
  if (directory < 0) return StintProxyFail(error, @"Proxy settings were restored, but the recovery directory is unavailable.");
  struct stat info;
  BOOL okay = !fstatat(directory, _path.lastPathComponent.fileSystemRepresentation, &info, AT_SYMLINK_NOFOLLOW) &&
    StintSecureJournal(info, _owner) && !unlinkat(directory, _path.lastPathComponent.fileSystemRepresentation, 0);
  if (okay) okay = fsync(directory) == 0;
  close(directory);
  return okay || StintProxyFail(error, @"Proxy settings were restored, but the recovery journal could not be safely removed. Stint will retry.");
}
@end

static BOOL StintValidateJournal(NSDictionary *journal, NSError **error) {
  if (![journal[@"version"] isKindOfClass:NSNumber.class] || ![journal[@"version"] isEqual:@1] ||
      ![journal[@"services"] isKindOfClass:NSDictionary.class] || ![journal[@"services"] count] ||
      [journal[@"services"] count] > StintServiceLimit || journal.count != 2)
    return StintProxyFail(error, @"The proxy recovery journal has an unsupported structure. See the manual recovery guide.");
  NSSet *keys = [NSSet setWithArray:StintOwnedKeys()];
  for (id serviceID in journal[@"services"]) {
    id entry = journal[@"services"][serviceID];
    if (![serviceID isKindOfClass:NSString.class] || ![serviceID length] || [serviceID length] > 256 ||
        ![entry isKindOfClass:NSDictionary.class] || [entry count] != 3 ||
        ![entry[@"original"] isKindOfClass:NSDictionary.class] || ![entry[@"missing"] isKindOfClass:NSArray.class] ||
        !StintEqual(entry[@"installed"], StintInstalledValues()))
      return StintProxyFail(error, @"The proxy recovery journal contains an invalid service snapshot. See the manual recovery guide.");
    NSMutableSet *seen = [NSMutableSet set];
    for (id key in entry[@"original"]) {
      id value = entry[@"original"][key];
      if (![keys containsObject:key] || !([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]))
        return StintProxyFail(error, @"The proxy recovery journal contains invalid original proxy values.");
      [seen addObject:key];
    }
    for (id key in entry[@"missing"]) {
      if (![keys containsObject:key] || [seen containsObject:key])
        return StintProxyFail(error, @"The proxy recovery journal contains ambiguous missing proxy keys.");
      [seen addObject:key];
    }
    if (![seen isEqualToSet:keys]) return StintProxyFail(error, @"The proxy recovery snapshot is incomplete. See the manual recovery guide.");
    // Stint never installs on top of an enabled HTTP(S) proxy. A forged or corrupt
    // original enable value must not resurrect a dead proxy during recovery.
    for (NSString *key in @[@"HTTPEnable", @"HTTPSEnable"]) {
      id value = entry[@"original"][key];
      if (value && (![value isKindOfClass:NSNumber.class] || [value boolValue]))
        return StintProxyFail(error, @"The recovery journal has an unsafe original proxy enable value. See the manual recovery guide.");
    }
  }
  return YES;
}

static BOOL StintCheckConfiguration(NSDictionary *configuration, NSArray<NSString *> *domains, BOOL installed, NSError **error) {
  NSArray *enableKeys = installed ? @[@"SOCKSEnable", @"ProxyAutoConfigEnable", @"ProxyAutoDiscoveryEnable"] :
    @[@"HTTPEnable", @"HTTPSEnable", @"SOCKSEnable", @"ProxyAutoConfigEnable", @"ProxyAutoDiscoveryEnable"];
  for (NSString *key in enableKeys) {
    id enabled = configuration[key];
    if (enabled && (![enabled isKindOfClass:NSNumber.class] || [enabled boolValue]))
      return StintProxyFail(error, @"An enabled proxy, PAC, or automatic proxy configuration conflicts with Stint. Turn it off before enabling website blocking.");
  }
  id exceptions = configuration[@"ExceptionsList"];
  if (exceptions && ![exceptions isKindOfClass:NSArray.class])
    return StintProxyFail(error, @"Network proxy exceptions are invalid or unsupported. Review them in System Settings before using Stint.");
  for (id exception in exceptions) {
    if (![exception isKindOfClass:NSString.class] ||
        (![(NSString *)exception isEqual:@"*.local"] && ![(NSString *)exception isEqual:@"169.254/16"]))
      return StintProxyFail(error, @"Custom network proxy exceptions may bypass website blocking. Remove them in System Settings before using Stint.");
    if ([exception isEqual:@"*.local"]) {
      for (NSString *domain in domains) if ([domain isEqual:@"local"] || [domain hasSuffix:@".local"])
        return StintProxyFail(error, @"The macOS local-network proxy exception bypasses a selected domain. Stint cannot block that domain with this configuration.");
    }
  }
  return YES;
}

@interface StintProxyPreferences ()
@property(nonatomic, readwrite, getter=isActive) BOOL active;
@property(nonatomic, strong) id<StintProxyPreferencesBackend> backend;
@property(nonatomic, strong) id<StintProxyJournal> journal;
@property(nonatomic, copy) NSArray<NSString *> *domains;
@property(nonatomic, copy) NSDictionary *snapshot;
@end

@implementation StintProxyPreferences
- (instancetype)initWithJournalPath:(NSString *)path expectedOwner:(uid_t)owner {
  StintFileProxyJournal *journal = [StintFileProxyJournal new]; journal.path = path; journal.owner = owner;
  return [self initWithBackend:[StintSCProxyBackend new] journal:journal];
}
- (instancetype)initWithBackend:(id<StintProxyPreferencesBackend>)backend journal:(id<StintProxyJournal>)journal {
  if ((self = [super init])) { _backend = backend; _journal = journal; _domains = @[]; }
  return self;
}
- (BOOL)activateForDomains:(NSArray<NSString *> *)domains error:(NSError **)error {
  if (error) *error = nil;
  if (![domains isKindOfClass:NSArray.class] || !domains.count || domains.count > 500)
    return StintProxyFail(error, @"No valid domains were supplied for proxy activation.");
  for (id domain in domains) if (![domain isKindOfClass:NSString.class] || ![domain length] || [domain length] > 253)
    return StintProxyFail(error, @"Invalid domain supplied for proxy activation.");
  _domains = [domains copy];
  if (_active) return [self validateActive:error];
  if (![self restore:error]) return NO;
  if (![_backend lock:error]) return NO;
  [_backend synchronize];
  NSError *failure = nil;
  NSDictionary *services = [_backend services:&failure];
  NSMutableDictionary *snapshots = [NSMutableDictionary dictionary];
  NSMutableDictionary *updates = [NSMutableDictionary dictionary];
  if (services) {
    for (NSString *serviceID in services) {
      NSDictionary *service = services[serviceID];
      if (![service[@"enabled"] boolValue]) continue;
      if (![service[@"protocolEnabled"] boolValue]) { failure = StintProxyError(@"An enabled network service has its proxy protocol disabled. Stint cannot protect this configuration."); break; }
      NSDictionary *configuration = service[@"proxies"];
      if (!StintCheckConfiguration(configuration, domains, NO, &failure)) break;
      NSMutableDictionary *original = [NSMutableDictionary dictionary];
      NSMutableArray *missing = [NSMutableArray array];
      for (NSString *key in StintOwnedKeys()) {
        id value = configuration[key];
        if (value) original[key] = value; else [missing addObject:key];
      }
      snapshots[serviceID] = @{@"original":original, @"missing":missing, @"installed":StintInstalledValues()};
      NSMutableDictionary *updated = [configuration mutableCopy];
      [updated addEntriesFromDictionary:StintInstalledValues()]; updates[serviceID] = updated;
    }
  }
  if (!failure && !snapshots.count) failure = StintProxyError(@"No enabled network service supports Stint’s HTTP and HTTPS proxy.");
  NSDictionary *journal = @{@"version":@1, @"services":snapshots};
  BOOL wrote = NO;
  if (!failure && StintValidateJournal(journal, &failure)) wrote = [_journal write:journal error:&failure];
  if (wrote) {
    _snapshot = journal;
    for (NSString *serviceID in updates) if (![_backend setProxies:updates[serviceID] forService:serviceID error:&failure]) break;
    if (!failure && [_backend commit:&failure]) (void)[_backend apply:&failure];
  }
  [_backend unlock];
  if (!failure && wrote) { _active = YES; return YES; }
  // A write failure may still have renamed a durable journal before fsync failed.
  // Restoration is safe to attempt even when no preference mutation took place.
  NSError *recovery = nil;
  if (![self restore:&recovery]) failure = StintProxyError([NSString stringWithFormat:@"%@ Recovery is pending: %@", failure.localizedDescription ?: @"Proxy activation failed.", recovery.localizedDescription]);
  if (error) *error = failure ?: StintProxyError(@"Proxy activation failed. Protection is unavailable.");
  return NO;
}
- (BOOL)restore:(NSError **)error {
  _active = NO;
  if (error) *error = nil;
  NSError *failure = nil;
  NSDictionary *journal = [_journal read:&failure];
  // A removed journal during this process must not strand an installed route.
  // Recreate the known snapshot durably before recovery; never replace a bad file.
  if (!journal && !failure && _snapshot) {
    if ([_journal write:_snapshot error:&failure]) journal = _snapshot;
  }
  if (!journal) { if (error) *error = failure; return !failure; }
  if (!StintValidateJournal(journal, error)) return NO;
  if (![_backend lock:error]) return NO;
  [_backend synchronize];
  NSDictionary *services = [_backend services:&failure];
  NSError *ambiguous = nil;
  if (services) {
    for (NSString *serviceID in journal[@"services"]) {
      NSDictionary *service = services[serviceID];
      if (!service) continue; // Removed services cannot retain an active route.
      NSDictionary *entry = journal[@"services"][serviceID];
      NSDictionary *current = service[@"proxies"];
      NSMutableDictionary *updated = [current mutableCopy];
      for (NSString *key in StintOwnedKeys()) {
        if (!StintEqual(current[key], entry[@"installed"][key])) continue;
        id original = entry[@"original"][key];
        if (original) updated[key] = original; else [updated removeObjectForKey:key];
      }
      BOOL unsafe = NO;
      for (NSString *prefix in @[@"HTTP", @"HTTPS"]) {
        id enabled = updated[[prefix stringByAppendingString:@"Enable"]];
        id host = updated[[prefix stringByAppendingString:@"Proxy"]];
        id port = updated[[prefix stringByAppendingString:@"Port"]];
        BOOL loopback = [host isEqual:@"127.0.0.1"] || [host isEqual:@"localhost"] || [host isEqual:@"::1"];
        if ([enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue] && loopback &&
            [port respondsToSelector:@selector(integerValue)] && [port integerValue] == 48197) unsafe = YES;
      }
      if (unsafe) {
        ambiguous = StintProxyError(@"An external edit left an enabled proxy pointing to Stint. Turn off Web Proxy and Secure Web Proxy for the affected service in System Settings → Network → Details → Proxies, then retry recovery. The recovery journal was retained.");
        continue;
      }
      if (![updated isEqual:current] && ![_backend setProxies:updated forService:serviceID error:&failure]) break;
    }
  }
  // Apply even if all owned values are already gone: the previous attempt may
  // have committed originals but failed to apply them to the live network.
  if (!failure && [_backend commit:&failure]) (void)[_backend apply:&failure];
  [_backend unlock];
  if (failure) { if (error) *error = failure; return NO; }
  if (ambiguous) { if (error) *error = ambiguous; return NO; }
  if (![_journal remove:error]) return NO;
  _snapshot = nil;
  return YES;
}
- (BOOL)validateActive:(NSError **)error {
  if (error) *error = nil;
  if (!_active) return StintProxyFail(error, @"Stint proxy routing is not active.");
  NSError *failure = nil;
  NSDictionary *journal = [_journal read:&failure];
  if (!journal && !failure) failure = StintProxyError(@"The active proxy recovery journal is missing. See the manual recovery guide.");
  if (journal && StintValidateJournal(journal, &failure) && [_backend lock:&failure]) {
    [_backend synchronize];
    NSDictionary *services = [_backend services:&failure];
    NSMutableSet *eligible = [NSMutableSet set];
    if (services) {
      for (NSString *serviceID in services) {
        NSDictionary *service = services[serviceID];
        if (![service[@"enabled"] boolValue]) continue;
        [eligible addObject:serviceID];
        NSDictionary *configuration = service[@"proxies"];
        if (![service[@"protocolEnabled"] boolValue] || !journal[@"services"][serviceID]) {
          failure = StintProxyError(@"Network services changed during focus. Stint restored its proxy settings; resume focus after reviewing the new configuration."); break;
        }
        for (NSString *key in StintOwnedKeys()) if (!StintEqual(configuration[key], StintInstalledValues()[key])) {
          failure = StintProxyError(@"Network proxy settings changed outside Stint. Stint is releasing its remaining settings; review the network configuration before resuming focus."); break;
        }
        if (failure || !StintCheckConfiguration(configuration, _domains, YES, &failure)) break;
      }
      if (!failure && ![eligible isEqualToSet:[NSSet setWithArray:[journal[@"services"] allKeys]]])
        failure = StintProxyError(@"An active network service was removed or disabled. Stint is restoring proxy settings before protection can resume.");
    }
    [_backend unlock];
  }
  if (!failure) return YES;
  _active = NO;
  NSError *recovery = nil;
  if (![self restore:&recovery]) failure = StintProxyError([NSString stringWithFormat:@"%@ Recovery is pending: %@", failure.localizedDescription, recovery.localizedDescription]);
  if (error) *error = failure;
  return NO;
}
@end

#ifdef STINT_PROXY_TESTING
id<StintProxyJournal> StintProxyTestJournal(NSString *path, uid_t expectedOwner) {
  StintFileProxyJournal *journal = [StintFileProxyJournal new]; journal.path = path; journal.owner = expectedOwner;
  return journal;
}
#endif
