#import <Foundation/Foundation.h>
#import "StintHostsFile.h"
#import "StintBlockerPolicy.h"
#import "../ProxyBlocker/StintProxyPreferences.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <poll.h>
#import <pwd.h>
#import <Security/Security.h>
#import <signal.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <sys/wait.h>
#import <spawn.h>
#import <fcntl.h>
#import <unistd.h>
#import <mach-o/dyld.h>
extern char **environ;

static NSString *const StintJob = @"io.github.albert2704.stint.hosts";
static NSString *const StintHelper = @"/Library/PrivilegedHelperTools/io.github.albert2704.stint.hosts";
static NSString *const StintConfigDirectory = @"/Library/Application Support/StintHosts";
static NSString *const StintLaunchPlist = @"/Library/LaunchDaemons/io.github.albert2704.stint.hosts.plist";
static NSString *const StintHostsPath = @"/private/etc/hosts";
static volatile sig_atomic_t StintStop;
static void StintSignal(int signal) { (void)signal; StintStop = 1; }
static double StintNow(void) { return NSDate.date.timeIntervalSince1970 * 1000; }
static NSString *StintPolicyPath(uid_t uid) {
  struct passwd *entry = getpwuid(uid);
  if (!entry || !entry->pw_dir || entry->pw_dir[0] != '/') return nil;
  return [[NSString stringWithUTF8String:entry->pw_dir] stringByAppendingPathComponent:@"Library/Application Support/Stint Website Blocker"];
}
static int StintRun(const char *executable, NSArray<NSString *> *arguments, BOOL quiet) {
  // Fixed executable/argument arrays only. No shell, domains or policy paths.
  char **argv = calloc(arguments.count+2, sizeof(char *)); argv[0] = (char *)executable;
  for (NSUInteger i=0; i<arguments.count; i++) argv[i+1] = (char *)arguments[i].UTF8String;
  pid_t pid; int status = 0;
  posix_spawn_file_actions_t actions;
  int error = posix_spawn_file_actions_init(&actions);
  if (error) { free(argv); return error; }
  // A missing launchd job is expected on first install. Keep real install and
  // bootout failures visible, without printing a misleading probe error.
  if (quiet) {
    error = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  }
  if (!error) error = posix_spawn(&pid, executable, &actions, NULL, argv, environ);
  posix_spawn_file_actions_destroy(&actions); free(argv);
  if (error) return error;
  double limit = NSProcessInfo.processInfo.systemUptime + (!strcmp(executable, "/bin/launchctl") ? 25 : 3);
  for (;;) {
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result == pid) break;
    if (result < 0 && errno != EINTR) return -1;
    if (NSProcessInfo.processInfo.systemUptime >= limit) {
      kill(pid, SIGKILL);
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
      return -1;
    }
    usleep(20000);
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
static void StintFlushDNS(void) {
  (void)StintRun("/usr/bin/dscacheutil", @[@"-flushcache"], NO);
  (void)StintRun("/usr/bin/killall", @[@"-HUP", @"mDNSResponder"], NO);
}
static int StintRootDirectory(NSString *path, BOOL create) {
  // All callers use fixed paths beneath /Library. Never follow a replaced link.
  int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  for (NSString *part in path.pathComponents) {
    if ([part isEqual:@"/"]) continue;
    if (create && mkdirat(current, part.UTF8String, 0755) && errno != EEXIST) { close(current); return -1; }
    int next = openat(current, part.UTF8String, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(current); current = next;
    struct stat info;
    if (current < 0) return -1;
    if (fstat(current, &info) || info.st_uid != 0 || (info.st_mode & 0022)) { close(current); return -1; }
  }
  return current;
}
static BOOL StintMatchesRunningCode(NSString *path) {
  // Compare the staged executable to this running helper's designated
  // requirement, including its ad hoc code hash. A changed source file must
  // never be promoted to a persistent root executable after sudo approval.
  SecCodeRef running = NULL; SecRequirementRef requirement = NULL; SecStaticCodeRef staged = NULL;
  OSStatus result = SecCodeCopySelf(kSecCSDefaultFlags, &running);
  if (result == errSecSuccess) result = SecCodeCopyDesignatedRequirement(running, kSecCSDefaultFlags, &requirement);
  if (result == errSecSuccess) result = SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &staged);
  if (result == errSecSuccess) result = SecStaticCodeCheckValidity(staged, kSecCSStrictValidate, requirement);
  if (staged) CFRelease(staged);
  if (requirement) CFRelease(requirement);
  if (running) CFRelease(running);
  return result == errSecSuccess;
}
static BOOL StintInstallFile(NSString *path, NSData *data, mode_t mode) {
  int directory = StintRootDirectory(path.stringByDeletingLastPathComponent, YES);
  if (directory < 0 || !data) { if (directory >= 0) close(directory); return NO; }
  NSString *temp = [@".stint-install-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = openat(directory, temp.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode);
  BOOL okay = fd >= 0; NSUInteger offset = 0;
  while (okay && offset < data.length) {
    ssize_t count = write(fd, (const uint8_t *)data.bytes+offset, data.length-offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) { okay = NO; break; }
    offset += count;
  }
  if (okay) okay = fchmod(fd, mode) == 0 && fsync(fd) == 0;
  if (fd >= 0) close(fd);
  if (okay && [path isEqual:StintHelper]) okay = StintMatchesRunningCode([path.stringByDeletingLastPathComponent stringByAppendingPathComponent:temp]);
  if (okay) okay = renameat(directory, temp.UTF8String, directory, path.lastPathComponent.UTF8String) == 0;
  if (!okay) unlinkat(directory, temp.UTF8String, 0);
  else (void)fsync(directory);
  close(directory); return okay;
}
static uid_t StintConfiguredUID(void) {
  int directory = StintRootDirectory(StintConfigDirectory, NO);
  if (directory < 0) return 0;
  NSData *data = StintReadBoundedAt(directory, "config.json", 0, 4096); close(directory);
  NSDictionary *config = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  if (![config isKindOfClass:NSDictionary.class] || ![config[@"version"] isEqual:@1]) return 0;
  id uid = config[@"uid"];
  if (![uid isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)uid) == CFBooleanGetTypeID()) return 0;
  double value = [uid doubleValue];
  return isfinite(value) && value >= 1 && value <= UINT32_MAX && floor(value) == value ? (uid_t)value : 0;
}
static BOOL StintReleaseHosts(void) {
  BOOL changed = NO; NSError *error = nil;
  BOOL okay = StintWriteHosts(StintHostsPath, @[], 0, &changed, &error);
  if (changed) StintFlushDNS();
  if (!okay) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  return okay;
}

@interface StintHostsEngine : NSObject
@property(nonatomic) uid_t owner;
@property(nonatomic, copy) NSData *startupInput;
@property(nonatomic, copy) NSData *lastInput;
@property(nonatomic, strong) StintBlockerPolicy *policy;
- (NSArray<NSString *> *)domainsForData:(NSData *)data now:(double)now uptime:(double)uptime;
@end
@implementation StintHostsEngine
- (NSArray<NSString *> *)domainsForData:(NSData *)data now:(double)now uptime:(double)uptime {
  if (data && [data isEqualToData:self.startupInput]) return @[];
  if (!self.lastInput || ![self.lastInput isEqualToData:data]) {
    self.lastInput = data;
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    self.policy = [StintBlockerPolicy policyWithDictionary:json now:now uptime:uptime];
    if (self.policy.ownerUID != self.owner || ![json isKindOfClass:NSDictionary.class])
      self.policy = [StintBlockerPolicy policyWithDictionary:nil now:now uptime:uptime];
  }
  return [self.policy isEffectiveAt:now uptime:uptime] ? self.policy.domains : @[];
}
@end

static StintProxyPreferences *StintRouting(void) {
  return [[StintProxyPreferences alloc] initWithJournalPath:[StintConfigDirectory stringByAppendingPathComponent:@"proxy-recovery.plist"] expectedOwner:0];
}
static BOOL StintRelease(void) {
  NSError *error = nil;
  BOOL proxies = [StintRouting() restore:&error];
  if (!proxies) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  BOOL hosts = StintReleaseHosts();
  return proxies && hosts;
}
static BOOL StintProxyPolicy(id value) {
  if (![value isKindOfClass:NSDictionary.class] || ![value[@"version"] isEqual:@2] ||
      ![value[@"proxyPort"] isKindOfClass:NSNumber.class] || ![value[@"proxyPort"] isEqual:@48197]) return NO;
  NSString *token = value[@"proxyToken"];
  return [token isKindOfClass:NSString.class] && token.length == 64 &&
    [token rangeOfString:@"^[0-9a-f]{64}$" options:NSRegularExpressionSearch].location != NSNotFound;
}
static BOOL StintProxyHealthy(NSDictionary *policy) {
  if (!StintProxyPolicy(policy)) return NO;
  int fd = socket(AF_INET, SOCK_STREAM, 0); if (fd < 0) return NO;
  fcntl(fd, F_SETFD, FD_CLOEXEC); fcntl(fd, F_SETFL, O_NONBLOCK);
  int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
  struct sockaddr_in address = {0}; address.sin_len = sizeof(address); address.sin_family = AF_INET;
  address.sin_port = htons(48197); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int result = connect(fd, (struct sockaddr *)&address, sizeof(address));
  struct pollfd item = {.fd = fd, .events = POLLOUT};
  if (result && errno != EINPROGRESS) { close(fd); return NO; }
  if (poll(&item, 1, 300) <= 0) { close(fd); return NO; }
  int socketError = 0; socklen_t size = sizeof(socketError);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &size) || socketError) { close(fd); return NO; }
  NSString *request = [NSString stringWithFormat:@"GET /_stint_health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Stint-Token: %@\r\nConnection: close\r\n\r\n", policy[@"proxyToken"]];
  NSData *bytes = [request dataUsingEncoding:NSASCIIStringEncoding];
  if (send(fd, bytes.bytes, bytes.length, 0) != (ssize_t)bytes.length) { close(fd); return NO; }
  NSMutableData *reply = [NSMutableData data]; double limit = NSProcessInfo.processInfo.systemUptime + 0.5;
  while (reply.length < 4096 && NSProcessInfo.processInfo.systemUptime < limit) {
    item.events = POLLIN;
    if (poll(&item, 1, 50) <= 0) continue;
    char buffer[1024]; ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
    if (count <= 0) { if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue; break; }
    [reply appendBytes:buffer length:(NSUInteger)count];
    NSString *text = [[NSString alloc] initWithData:reply encoding:NSASCIIStringEncoding];
    NSRange end = [text rangeOfString:@"\r\n\r\n"];
    if (text && [text hasPrefix:@"HTTP/1.1 200 "] && end.location != NSNotFound &&
        [[text substringFromIndex:NSMaxRange(end)] isEqualToString:policy[@"proxyToken"]]) { close(fd); return YES; }
  }
  close(fd); return NO;
}
static int StintServe(void) {
  uid_t owner = StintConfiguredUID();
  if (!owner) { StintRelease(); return 1; }
  int root = StintRootDirectory(StintConfigDirectory, NO);
  if (root < 0) return 1;
  int lock = openat(root, "daemon.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600); close(root);
  struct stat lockInfo;
  if (lock < 0 || fstat(lock, &lockInfo) || !S_ISREG(lockInfo.st_mode) || lockInfo.st_uid || lockInfo.st_nlink != 1 || (lockInfo.st_mode & 0022) || flock(lock, LOCK_EX | LOCK_NB)) { if (lock >= 0) close(lock); return 1; }
  StintHostsEngine *engine = [StintHostsEngine new]; engine.owner = owner;
  int startupDirectory = StintOpenPolicyDirectory(StintPolicyPath(owner), owner);
  if (startupDirectory >= 0) {
    engine.startupInput = StintReadBoundedAt(startupDirectory, "policy.json", owner, 128*1024);
    close(startupDirectory);
  }
  StintProxyPreferences *routing = StintRouting();
  BOOL hostsRecovered = StintReleaseHosts();
  signal(SIGTERM, StintSignal); signal(SIGINT, StintSignal);
  double lastStatus = 0; NSDictionary *previousStatus = nil;
  BOOL recovered = [routing restore:NULL];
  NSString *failedSession = nil; NSString *failureMessage = nil;
  while (!StintStop) {
    @autoreleasepool {
      double now = StintNow();
      int directory = StintOpenPolicyDirectory(StintPolicyPath(owner), owner);
      NSData *data = directory >= 0 ? StintReadBoundedAt(directory, "policy.json", owner, 128*1024) : nil;
      id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
      NSArray *domains = [engine domainsForData:data now:now uptime:NSProcessInfo.processInfo.systemUptime];
      NSError *error = nil;
      if (!hostsRecovered) hostsRecovered = StintReleaseHosts();
      if (!recovered) recovered = [routing restore:&error];
      NSString *session = engine.policy.session;
      if (failedSession && ![failedSession isEqualToString:session]) { failedSession = nil; failureMessage = nil; }
      BOOL wanted = domains.count && StintProxyPolicy(json);
      BOOL healthy = wanted && StintProxyHealthy(json);
      // Recovery and socket probing can outlast the lease sampled above.
      if (![engine.policy isEffectiveAt:StintNow() uptime:NSProcessInfo.processInfo.systemUptime]) { wanted = NO; healthy = NO; }
      BOOL okay = recovered && hostsRecovered;
      if (okay && healthy && !failedSession) {
        if (routing.active) {
          okay = [routing validateActive:&error];
          if (!okay) { failedSession = session; failureMessage = error.localizedDescription ?: @"Network settings changed. Website blocking is released for this focus. Start a new focus to retry."; }
        }
        if (okay) okay = [routing activateForDomains:domains error:&error];
      } else if (okay) {
        okay = [routing restore:&error];
      }
      if (!okay) { NSError *releaseError = nil; recovered = [routing restore:&releaseError]; if (releaseError) error = releaseError; }
      BOOL active = okay && healthy && !failedSession && routing.active;
      NSString *message = error.localizedDescription;
      if (okay && wanted && !healthy) message = @"Stint's local proxy is not responding. Previous network settings have been restored. Reopen Stint to retry.";
      else if (failedSession) message = failureMessage;
      else if (okay) message = active ? @"Website proxy is active for browsers using macOS network settings. Browsers stay open; HTTPS stays encrypted." : @"Proxy helper is ready. Normal network settings are restored until your next running focus.";
      else if (!message) message = @"Could not recover website blocking settings. See the recovery guide before starting another focus.";
      NSDictionary *state = @{@"version": @2, @"transport": @"proxy", @"ownerUID": @(owner),
        @"status": okay && !failedSession && (!wanted || healthy) ? @"configured" : @"unavailable", @"active": @(active), @"sessionId": active ? session : @"", @"message": message};
      if (directory >= 0 && (NSProcessInfo.processInfo.systemUptime-lastStatus >= 5 || ![state isEqualToDictionary:previousStatus])) {
        NSMutableDictionary *status = [state mutableCopy]; status[@"heartbeatMilliseconds"] = @(now);
        if (StintWriteStatusAt(directory, status)) { lastStatus = NSProcessInfo.processInfo.systemUptime; previousStatus = state; }
      }
      if (directory >= 0) close(directory);
    }
    sleep(1);
  }
  BOOL released = [routing restore:NULL];
  int directory = StintOpenPolicyDirectory(StintPolicyPath(owner), owner);
  if (directory >= 0) {
    StintWriteStatusAt(directory, @{@"version": @2, @"transport": @"proxy", @"ownerUID": @(owner), @"status": @"notInstalled", @"active": @NO,
      @"heartbeatMilliseconds": @(StintNow()), @"message": released ? @"Website helper stopped and network settings restored. Run setup to enable it again." : @"Helper stopped but proxy recovery failed. See the recovery guide."});
    close(directory);
  }
  close(lock); return released ? 0 : 1;
}

#ifndef STINT_HOSTS_TEST
int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2 || ![@[@"install", @"uninstall", @"release", @"serve"] containsObject:@(argv[1])]) {
      fprintf(stderr, "Usage: StintHostsHelper install | uninstall | release | serve\n"); return 2;
    }
    if (geteuid() != 0) { fprintf(stderr, "Administrator approval is required. Run the bundled setup command.\n"); return 1; }
    umask(022);
    NSString *action = @(argv[1]);
    if ([action isEqual:@"serve"]) return StintServe();
    const char *sudoUID = getenv("SUDO_UID"); char *end = NULL;
    unsigned long parsed = sudoUID ? strtoul(sudoUID, &end, 10) : 0;
    if (!sudoUID || !*sudoUID || !end || *end || parsed == 0 || parsed > UINT32_MAX || !getpwuid((uid_t)parsed)) {
      fprintf(stderr, "Run this command using sudo from your own Mac account.\n"); return 1;
    }
    uid_t owner = (uid_t)parsed, existing = StintConfiguredUID();
    if (existing && existing != owner) { fprintf(stderr, "This helper belongs to another Mac account. That account must remove it first.\n"); return 1; }
    // Stop old jobs before editing/copying. If bootout fails for a loaded job,
    // abort instead of racing a still-running privileged writer.
    NSString *service = [@"system/" stringByAppendingString:StintJob];
    int loaded = StintRun("/bin/launchctl", @[@"print", service], YES);
    if (loaded == 0 && StintRun("/bin/launchctl", @[@"bootout", service], NO) != 0) return 1;
    int lockDirectory = StintRootDirectory(StintConfigDirectory, YES);
    if (lockDirectory < 0) return 1;
    int installLock = openat(lockDirectory, "daemon.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    close(lockDirectory);
    struct stat lockInfo;
    if (installLock < 0 || fstat(installLock, &lockInfo) || !S_ISREG(lockInfo.st_mode) || lockInfo.st_uid || lockInfo.st_nlink != 1 || (lockInfo.st_mode & 0022)) return 1;
    double lockDeadline = NSProcessInfo.processInfo.systemUptime + 25;
    while (flock(installLock, LOCK_EX | LOCK_NB)) {
      if (errno != EWOULDBLOCK || NSProcessInfo.processInfo.systemUptime >= lockDeadline) {
        fprintf(stderr, "Previous helper has not stopped. No installation files or hosts entries were changed by this command. Try again.\n"); return 1;
      }
      usleep(50000);
    }
    if (!StintRelease()) return 1;
    if ([action isEqual:@"release"]) { puts("Stint proxy settings restored, old hosts entries released and helper stopped. Run setup to enable it again."); return 0; }
    if ([action isEqual:@"uninstall"]) {
      for (NSString *path in @[StintLaunchPlist, StintHelper, [StintConfigDirectory stringByAppendingPathComponent:@"config.json"]]) {
        int directory = StintRootDirectory(path.stringByDeletingLastPathComponent, NO);
        if (directory >= 0) { if (unlinkat(directory, path.lastPathComponent.UTF8String, 0) && errno != ENOENT) { close(directory); return 1; } close(directory); }
      }
      puts("Stint website helper removed. Your saved blocklist and unrelated network settings were kept."); return 0;
    }
    NSString *policyPath = StintPolicyPath(owner);
    int policyDir = policyPath ? StintOpenPolicyDirectory(policyPath, owner) : -1;
    if (policyDir < 0) { fprintf(stderr, "Open Stint and choose Set up website blocker first. Its settings folder must belong to your account.\n"); return 1; }
    close(policyDir);
    uint32_t size = 0; _NSGetExecutablePath(NULL, &size); char *executable = calloc(size, 1);
    if (_NSGetExecutablePath(executable, &size)) { free(executable); return 1; }
    NSData *binary = [NSData dataWithContentsOfFile:@(executable)]; free(executable);
    NSDictionary *config = @{@"version": @1, @"uid": @(owner)};
    NSDictionary *job = @{@"Label": StintJob, @"ProgramArguments": @[StintHelper, @"serve"], @"RunAtLoad": @YES,
      @"KeepAlive": @YES, @"ThrottleInterval": @5, @"ExitTimeOut": @20, @"ProcessType": @"Background"};
    NSData *configData = [NSJSONSerialization dataWithJSONObject:config options:0 error:NULL];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:job format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    if (!StintInstallFile(StintHelper, binary, 0755) ||
        !StintInstallFile([StintConfigDirectory stringByAppendingPathComponent:@"config.json"], configData, 0600) ||
        !StintInstallFile(StintLaunchPlist, plist, 0644)) { fprintf(stderr, "Helper installation failed. Run setup again or use the recovery command.\n"); return 1; }
    close(installLock); // New daemon may acquire the lock only after installation is complete.
    if (StintRun("/bin/launchctl", @[@"bootstrap", @"system", StintLaunchPlist], NO)) { fprintf(stderr, "macOS did not start the helper. Run setup again or use Remove Website Blocker.command.\n"); return 1; }
    puts("Website helper installed. Return to Stint and choose Refresh. No Apple subscription is needed."); return 0;
  }
}
#endif
