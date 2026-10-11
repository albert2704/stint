#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/xattr.h>
#import <fcntl.h>
#import <unistd.h>
#define STINT_HOSTS_TEST 1
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../macos/HostsBlocker/StintHostsHelper.m"
#pragma clang diagnostic pop
#import "../macos/Runner/StintWebsiteBlocker.m"
static NSUInteger checks;
static void Check(BOOL okay, NSString *message) {
  if (!okay) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } checks++;
}
static NSData *Bytes(NSString *s) { return [s dataUsingEncoding:NSISOLatin1StringEncoding]; }
static NSDictionary *Policy(double now, double duration) {
  return @{@"version":@1, @"active":@YES, @"ownerUID":@(getuid()), @"sessionId":@"focus-a", @"domains":@[@"example.com"],
    @"issuedAtMilliseconds":@(now), @"deadlineMilliseconds":@(now+60000), @"leaseExpiresAt":@(now+duration)};
}
static NSData *JSON(id value) { return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:NULL]; }
@interface HostProbe : StintWebsiteBlocker
@property(nonatomic, copy) NSString *fixture;
@property(nonatomic, strong) NSURL *commandURL;
@property(nonatomic, copy) NSString *commandName;
@property(nonatomic, strong) NSURL *revealedURL;
@end
@implementation HostProbe
- (StintLocalProxy *)makeProxy { return [[StintLocalProxy alloc] initWithPort:0]; }
- (NSString *)policyDirectory { return self.fixture; }
- (NSURL *)setupCommandURL:(NSString *)name { self.commandName=name; return self.commandURL; }
- (void)revealSetupCommand:(NSURL *)script { self.revealedURL=script; }
@end
int main(void) {
  @autoreleasepool {
    for (NSString *original in @[@"", @"127.0.0.1 localhost\n# private comment\n", @"::1 localhost\r\n# keep CRLF\r\n", @"# no final newline", @"# byte ÿ\n"]) {
      NSError *error = nil; NSData *before = Bytes(original);
      NSData *blocked = StintHostsData(before, @[@"example.com"], &error);
      Check(blocked && !error, @"valid hosts transformation");
      NSString *text = [[NSString alloc] initWithData:blocked encoding:NSISOLatin1StringEncoding];
      Check([text containsString:@"127.0.0.1 example.com\n::1 example.com\n127.0.0.1 www.example.com\n::1 www.example.com\n"], @"both families and www alias");
      Check(![text containsString:@"*.example.com"], @"never claim wildcard hosts support");
      Check([StintHostsData(blocked, @[], &error) isEqualToData:before], @"release restores every original byte");
      Check([StintHostsData(blocked, @[@"example.com"], &error) isEqualToData:blocked], @"repeat is idempotent");
      NSData *edited = [[text stringByAppendingString:@"# added by another tool\n"] dataUsingEncoding:NSISOLatin1StringEncoding];
      Check([StintHostsData(edited, @[], &error) isEqualToData:Bytes([original stringByAppendingString:@"# added by another tool\n"])], @"external suffix preserved");
      NSData *replacement = StintHostsData(blocked, @[@"different.test"], &error);
      Check([StintHostsData(replacement, @[], &error) isEqualToData:before], @"domain replacement retains original");
    }
    for (NSString *bad in @[@"# BEGIN STINT HOSTS\n", @"# END STINT HOSTS v1\n", @"# BEGIN STINT HOSTS v1 join=0\ncustom text\n# END STINT HOSTS v1\n", @"# BEGIN STINT HOSTS v1 join=1\n# END STINT HOSTS v1\n", @"# BEGIN STINT HOSTS v1 join=0\n# BEGIN STINT HOSTS v1 join=0\n# END STINT HOSTS v1\n# END STINT HOSTS v1\n"]) {
      NSError *error = nil;
      Check(!StintHostsData(Bytes(bad), @[], &error) && error, @"ambiguous or edited managed block never overwritten");
    }
    for (NSString *domain in @[@"localhost", @"127.0.0.1", @"*.example.com", @"a.123", @"bad..test", @"bad\nname.com", @"EXAMPLE.com", @"a.localhost"])
      Check(!StintHostsData(Bytes(@"# intact"), @[domain], NULL), @"invalid host cannot become a root hosts entry");
    NSMutableArray *tooMany = [NSMutableArray array]; for (int i=0;i<201;i++) [tooMany addObject:[NSString stringWithFormat:@"a%d.test", i]];
    Check(!StintHostsData(Bytes(@""), tooMany, NULL), @"domain bound");
    Check(!StintHostsData([NSMutableData dataWithLength:2*1024*1024+1], @[], NULL), @"hosts size bound");
    NSData *dedup = StintHostsData(Bytes(@""), @[@"example.com", @"www.example.com"], NULL);
    Check([[[NSString alloc] initWithData:dedup encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"127.0.0.1 www.example.com"].count == 2, @"explicit www does not duplicate alias");

    Check(!StintHostsData(Bytes(@"203.0.113.1 other.test www.example.com # keep me\n"), @[@"example.com"], NULL), @"existing routable alias conflict surfaced");
    Check(StintHostsData(Bytes(@"127.0.0.2 example.com\n:: example.com\n"), @[@"example.com"], NULL) != nil, @"existing local sink mappings allowed");
    StintHostsEngine *engine = [StintHostsEngine new]; engine.owner = getuid(); engine.startupInput = JSON(Policy(99999,30000));
    Check(![engine domainsForData:JSON(Policy(99999,30000)) now:100000 uptime:1].count, @"pre-restart state does not reactivate blocking");
    NSData *valid = JSON(Policy(100000,30000));
    Check([engine domainsForData:valid now:100000 uptime:2].count == 1, @"fresh focus begins");
    Check([engine domainsForData:valid now:110000 uptime:12].count == 1, @"unchanged valid focus retained");
    Check(![engine domainsForData:valid now:100001 uptime:32].count, @"same policy cannot renew monotonic deadline after clock rollback");
    Check([engine domainsForData:JSON(Policy(110000,30000)) now:110000 uptime:33].count == 1, @"fresh heartbeat renews");
    Check(![engine domainsForData:JSON(@{@"active":@NO}) now:110000 uptime:34].count, @"pause releases immediately");
    Check(![engine domainsForData:nil now:110000 uptime:35].count, @"missing policy releases");
    NSMutableDictionary *wrong = [Policy(110000,30000) mutableCopy]; wrong[@"ownerUID"] = @(getuid()+1);
    Check(![engine domainsForData:JSON(wrong) now:110000 uptime:36].count, @"wrong owner cannot enable");
    for (id invalid in @[NSNull.null, @[], @{}, @{@"active":@YES}, Policy(110000,30001), Policy(110000,0), Policy(200000,30000)])
      Check(![engine domainsForData:JSON(invalid) now:110000 uptime:37].count, @"invalid policy releases");
    Check([engine domainsForData:JSON(Policy(90000,30000)) now:90000 uptime:37].count == 1, @"fresh heartbeats work after wall clock rollback past startup");
    NSDictionary *validDict = Policy(110000,30000);
    for (NSString *key in validDict) {
      NSMutableDictionary *missing = [validDict mutableCopy]; [missing removeObjectForKey:key];
      Check(![engine domainsForData:JSON(missing) now:110000 uptime:38].count, @"missing required field releases");
    }
    for (id bad in @[@(NAN), @(INFINITY), @YES, @"12345"]) {
      for (NSString *key in @[@"issuedAtMilliseconds", @"deadlineMilliseconds", @"leaseExpiresAt"]) {
        NSMutableDictionary *invalid = [validDict mutableCopy]; invalid[key] = bad;
        Check(![[StintBlockerPolicy policyWithDictionary:invalid now:110000 uptime:38] isEffectiveAt:110000 uptime:38], @"bad numeric time rejected");
      }
    }
    Check(![engine domainsForData:JSON(Policy(110000,30000)) now:140000 uptime:39].count, @"wall expiry releases");

    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"stint-hosts-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    Check([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL], @"create private fixtures");
    NSString *path = [folder stringByAppendingPathComponent:@"hosts"];
    NSData *original = Bytes(@"127.0.0.1 localhost\n# fixture only\n");
    Check([original writeToFile:path atomically:YES], @"write hosts fixture"); chmod(path.fileSystemRepresentation,0640);
    Check(setxattr(path.fileSystemRepresentation,"com.stint.test","keep",4,0,0)==0, @"fixture extended attribute");
    NSString *copy = [folder stringByAppendingPathComponent:@"helper-copy"];
    NSData *executable = [NSData dataWithContentsOfFile:NSProcessInfo.processInfo.arguments.firstObject];
    Check([executable writeToFile:copy atomically:YES], @"stage executable fixture"); chmod(copy.fileSystemRepresentation,0755);
    Check(StintMatchesRunningCode(copy), @"copied ad hoc code matches running helper requirement");
    Check([Bytes(@"different code") writeToFile:copy atomically:YES] && !StintMatchesRunningCode(copy), @"substituted helper cannot pass installation check");
    BOOL changed = NO; NSError *error = nil;
    Check(StintWriteHosts(path,@[@"example.com"],getuid(),&changed,&error) && changed, @"real atomic fixture write");
    struct stat info; stat(path.fileSystemRepresentation,&info);
    Check((info.st_mode & 0777)==0640 && info.st_uid==getuid(), @"mode and owner preserved");
    char attribute[4]; Check(getxattr(path.fileSystemRepresentation,"com.stint.test",attribute,4,0,0)==4 && !memcmp(attribute,"keep",4), @"extended attribute preserved");
    Check(StintWriteHosts(path,@[@"example.com"],getuid(),&changed,&error) && !changed, @"no write for identical policy");
    Check(StintWriteHosts(path,@[],getuid(),&changed,&error) && changed && [[NSData dataWithContentsOfFile:path] isEqual:original], @"real release keeps original bytes");
    NSString *alias = [folder stringByAppendingPathComponent:@"alias"];
    symlink(path.fileSystemRepresentation,alias.fileSystemRepresentation); error=nil;
    Check(!StintWriteHosts(alias,@[@"example.com"],getuid(),&changed,&error), @"symlink target rejected"); unlink(alias.fileSystemRepresentation);
    link(path.fileSystemRepresentation,alias.fileSystemRepresentation); error=nil;
    Check(!StintWriteHosts(path,@[@"example.com"],getuid(),&changed,&error), @"hardlinked hosts rejected"); unlink(alias.fileSystemRepresentation);
    chmod(path.fileSystemRepresentation,0666); error=nil;
    Check(!StintWriteHosts(path,@[@"example.com"],getuid(),&changed,&error), @"unsafe hosts mode rejected"); chmod(path.fileSystemRepresentation,0640);
    error=nil; Check(!StintWriteHosts(path,@[@"example.com"],getuid()+1,&changed,&error), @"wrong hosts owner rejected");
    Check([[NSData dataWithContentsOfFile:path] isEqual:original], @"failed writes never touched fixture");
    Check(chflags(path.fileSystemRepresentation, UF_IMMUTABLE) == 0, @"lock fixture only"); error=nil;
    Check(!StintWriteHosts(path,@[@"example.com"],getuid(),&changed,&error) && !changed, @"immutable hosts rejected before staging");
    Check(chflags(path.fileSystemRepresentation, 0) == 0, @"unlock fixture only");
    int directory = open(folder.fileSystemRepresentation,O_RDONLY|O_DIRECTORY);
    Check(!StintReadBoundedAt(directory,"hosts",getuid(),4), @"reader byte limit");
    symlink(path.fileSystemRepresentation,alias.fileSystemRepresentation);
    Check(!StintReadBoundedAt(directory,"alias",getuid(),8192), @"policy reader rejects symlink"); unlink(alias.fileSystemRepresentation);
    mkfifo(alias.fileSystemRepresentation,0600);
    Check(!StintReadBoundedAt(directory,"alias",getuid(),8192), @"FIFO cannot stall helper"); unlink(alias.fileSystemRepresentation);
    Check(StintWriteStatusAt(directory,@{@"version":@1,@"status":@"configured"}), @"status is atomically written"); close(directory);
    HostProbe *host = [HostProbe new]; host.fixture=folder;
    [host update:Policy(StintNow(),30000)];
    NSDictionary *written = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"policy.json"]] options:0 error:NULL];
    Check([written[@"active"] boolValue] && [written[@"ownerUID"] unsignedIntValue]==getuid() && [written[@"version"] isEqual:@2], @"native host publishes validated v2 focus policy");
    Check([written[@"proxyToken"] length] == 64 && [written[@"proxyPort"] unsignedIntValue] > 0, @"native policy identifies the authenticated local proxy");
    __block NSString *status;
    [host statusWithReply:^(NSDictionary *value){status=value[@"status"];}];
    Check([status isEqual:@"notInstalled"], @"user-owned fake status cannot claim root helper ready");
    [host update:@{@"active":@NO}];
    written=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"policy.json"]] options:0 error:NULL];
    Check(![written[@"active"] boolValue], @"native pause publishes inactive state");
    host.commandURL=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Install Website Blocker.command"]];
    __block NSDictionary *setup;
    [host enableWithReply:^(NSDictionary *value){setup=value;}];
    Check([host.commandName isEqual:@"Install Website Blocker"] && [host.revealedURL isEqual:host.commandURL], @"setup reveals the bundled command instead of sending it to Terminal");
    Check([setup[@"status"] isEqual:@"approvalRequired"] && [setup[@"message"] containsString:@"Finder"] && [setup[@"message"] containsString:@"Install Website Blocker.command"], @"setup gives explicit manual Finder instructions");
    [host statusWithReply:^(NSDictionary *value){setup=value;}];
    Check([setup[@"status"] isEqual:@"approvalRequired"] && [setup[@"message"] containsString:@"Finder"], @"refresh retains manual setup instructions while helper absent");
    host.commandURL=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"Remove Website Blocker.command"]];
    [host removeWithReply:^(NSDictionary *value){setup=value;}];
    Check([host.commandName isEqual:@"Remove Website Blocker"] && [host.revealedURL isEqual:host.commandURL] && [setup[@"message"] containsString:@"Remove Website Blocker.command"], @"removal uses the same safe reveal flow with correct command");
    NSDictionary *afterSetup=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"policy.json"]] options:0 error:NULL];
    Check([afterSetup isEqual:written], @"revealing setup never changes focus policy");
    host.commandURL=nil; host.revealedURL=nil;
    [host enableWithReply:^(NSDictionary *value){setup=value;}];
    Check([setup[@"status"] isEqual:@"unavailable"] && !host.revealedURL, @"missing setup command reports failure without claiming handoff");
    Check([NSFileManager.defaultManager removeItemAtPath:folder error:NULL], @"remove only temporary fixtures");
    printf("Hosts blocker: %lu checks passed (temporary fixtures only; no privileged installation or real hosts edits).\n", (unsigned long)checks);
  }
  return 0;
}
