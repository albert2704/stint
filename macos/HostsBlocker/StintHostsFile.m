#import "StintHostsFile.h"
#import "StintBlockerPolicy.h"
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <copyfile.h>
#import <arpa/inet.h>

static NSError *StintFileError(NSString *message) {
  return [NSError errorWithDomain:@"StintHosts" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSData *StintAmbiguous(NSError **error) {
  if (error) *error = StintFileError(@"Stint’s hosts markers were edited or are ambiguous. No hosts content was changed. See the recovery guide.");
  return nil;
}
NSData *StintHostsData(NSData *original, NSArray<NSString *> *domains, NSError **error) {
  NSArray *valid = StintValidatedDomains(domains);
  if (!valid || original.length > 2 * 1024 * 1024) { if (error) *error = StintFileError(@"Hosts input is invalid or too large."); return nil; }
  NSString *source = [[NSString alloc] initWithData:original encoding:NSISOLatin1StringEncoding];
  if (!source) { if (error) *error = StintFileError(@"Cannot decode hosts bytes."); return nil; }
  NSString *beginPrefix = @"# BEGIN STINT HOSTS", *endPrefix = @"# END STINT HOSTS";
  NSArray *begins = [source componentsSeparatedByString:beginPrefix], *ends = [source componentsSeparatedByString:endPrefix];
  if (begins.count != ends.count || begins.count > 2) return StintAmbiguous(error);
  NSString *base = source;
  if (begins.count == 2) {
    NSRange begin = [source rangeOfString:beginPrefix], end = [source rangeOfString:endPrefix];
    if (end.location < begin.location || (begin.location && [source characterAtIndex:begin.location-1] != '\n')) return StintAmbiguous(error);
    NSRange lineEnd = [source rangeOfString:@"\n" options:0 range:NSMakeRange(begin.location, source.length-begin.location)];
    if (lineEnd.location == NSNotFound) return StintAmbiguous(error);
    NSString *header = [source substringWithRange:NSMakeRange(begin.location, lineEnd.location-begin.location+1)];
    BOOL join = [header isEqual:@"# BEGIN STINT HOSTS v1 join=1\n"];
    if (!join && ![header isEqual:@"# BEGIN STINT HOSTS v1 join=0\n"]) return StintAmbiguous(error);
    NSString *footer = @"# END STINT HOSTS v1\n";
    if (end.location < NSMaxRange(lineEnd) || ![[source substringFromIndex:end.location] hasPrefix:footer]) return StintAmbiguous(error);
    NSString *body = [source substringWithRange:NSMakeRange(NSMaxRange(lineEnd), end.location-NSMaxRange(lineEnd))];
    NSArray *lines = [body componentsSeparatedByString:@"\n"];
    if (lines.count % 2 != 1 || ![lines.lastObject isEqual:@""]) return StintAmbiguous(error);
    for (NSUInteger i = 0; i + 1 < lines.count; i += 2) {
      NSString *v4 = lines[i], *v6 = lines[i+1];
      if (![v4 hasPrefix:@"127.0.0.1 "]) return StintAmbiguous(error);
      NSString *host = [v4 substringFromIndex:10];
      if (!StintValidatedDomains(@[host]) || ![v6 isEqual:[@"::1 " stringByAppendingString:host]]) return StintAmbiguous(error);
    }
    NSUInteger start = begin.location;
    if (join) { if (!start || [source characterAtIndex:start-1] != '\n') return StintAmbiguous(error); start--; }
    base = [source stringByReplacingCharactersInRange:NSMakeRange(start, end.location+footer.length-start) withString:@""];
  }
  if (!valid.count) return [base dataUsingEncoding:NSISOLatin1StringEncoding];
  BOOL join = base.length && ![base hasSuffix:@"\n"];
  NSMutableString *output = [base mutableCopy];
  if (join) [output appendString:@"\n"];
  [output appendFormat:@"# BEGIN STINT HOSTS v1 join=%d\n", join];
  NSMutableOrderedSet *hosts = [NSMutableOrderedSet orderedSet];
  for (NSString *domain in valid) {
    [hosts addObject:domain];
    NSString *www = [@"www." stringByAppendingString:domain];
    if (![domain hasPrefix:@"www."] && www.length <= 253) [hosts addObject:www];
  }
  // Preserve existing mappings, but do not claim success if they supply an
  // alternate routable address for a selected host.
  for (NSString *line in [base componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    NSString *entry = [line componentsSeparatedByString:@"#"].firstObject;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [entry componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) if (part.length) [parts addObject:part];
    if (parts.count < 2) continue;
    struct in_addr v4; struct in6_addr v6;
    const char *address = [parts.firstObject UTF8String];
    BOOL local = (inet_pton(AF_INET, address, &v4) == 1 && ((ntohl(v4.s_addr) >> 24) == 127 || v4.s_addr == 0)) ||
      (inet_pton(AF_INET6, address, &v6) == 1 && (IN6_IS_ADDR_LOOPBACK(&v6) || IN6_IS_ADDR_UNSPECIFIED(&v6)));
    if (local) continue;
    for (NSUInteger i=1; i<parts.count; i++) {
      NSString *alias = [parts[i] lowercaseString];
      if ([alias hasSuffix:@"."]) alias = [alias substringToIndex:alias.length-1];
      if ([hosts containsObject:alias]) {
        if (error) *error = StintFileError(@"An existing hosts entry conflicts with your blocklist. Stint kept it unchanged. Resolve the mapping before blocking this website.");
        return nil;
      }
    }
  }
  for (NSString *host in hosts) [output appendFormat:@"127.0.0.1 %@\n::1 %@\n", host, host];
  [output appendString:@"# END STINT HOSTS v1\n"];
  return [output dataUsingEncoding:NSISOLatin1StringEncoding];
}

static NSData *StintReadFD(int fd, NSUInteger limit) {
  if (lseek(fd, 0, SEEK_SET) < 0) return nil;
  NSMutableData *data = [NSMutableData data]; unsigned char buffer[4096]; ssize_t count;
  while ((count = read(fd, buffer, sizeof(buffer))) > 0) {
    if (data.length + count > limit) return nil;
    [data appendBytes:buffer length:(NSUInteger)count];
  }
  return count < 0 ? nil : data;
}
static BOOL StintRegular(struct stat info, uid_t owner) {
  return S_ISREG(info.st_mode) && info.st_uid == owner && info.st_nlink == 1 && !(info.st_mode & 0022);
}
static BOOL StintWriteFD(int fd, NSData *data) {
  const uint8_t *bytes = data.bytes; NSUInteger offset = 0;
  while (offset < data.length) {
    ssize_t count = write(fd, bytes+offset, data.length-offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return NO;
    offset += count;
  }
  return fsync(fd) == 0;
}
int StintOpenPolicyDirectory(NSString *path, uid_t owner) {
  if (![path hasPrefix:@"/"]) return -1;
  int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  for (NSString *part in path.pathComponents) {
    if ([part isEqual:@"/"]) continue;
    if ([part isEqual:@".."] || [part isEqual:@"."]) { close(current); return -1; }
    int next = openat(current, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(current); current = next;
    if (current < 0) return -1;
    struct stat info;
    if (fstat(current, &info) || !S_ISDIR(info.st_mode) || (info.st_uid != 0 && info.st_uid != owner) || (info.st_mode & 0022)) { close(current); return -1; }
  }
  struct stat info;
  if (fstat(current, &info) || info.st_uid != owner) { close(current); return -1; }
  return current;
}
NSData *StintReadBoundedAt(int directory, const char *name, uid_t owner, NSUInteger limit) {
  int fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return nil;
  struct stat info; NSData *data = nil;
  if (!fstat(fd, &info) && StintRegular(info, owner) && info.st_size >= 0 && (uint64_t)info.st_size <= limit) data = StintReadFD(fd, limit);
  close(fd); return data;
}
BOOL StintWriteStatusAt(int directory, NSDictionary *status) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:NULL];
  NSString *temp = [@".stint-status-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = openat(directory, temp.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
  if (fd < 0) return NO;
  BOOL okay = StintWriteFD(fd, data); close(fd);
  if (okay) okay = renameat(directory, temp.UTF8String, directory, "helper-status.json") == 0;
  if (!okay) unlinkat(directory, temp.UTF8String, 0);
  return okay;
}
BOOL StintWriteHosts(NSString *path, NSArray<NSString *> *domains, uid_t owner, BOOL *changed, NSError **error) {
  if (changed) *changed = NO;
  // All production callers pass the fixed /private/etc/hosts path and uid 0.
  int directory = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (directory < 0) { if (error) *error = StintFileError(@"Cannot open the hosts directory."); return NO; }
  int fd = openat(directory, path.lastPathComponent.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
  int temporary = -1; NSString *tempName = nil; BOOL okay = NO;
  struct stat info;
  if (fd < 0 || flock(fd, LOCK_EX | LOCK_NB) || fstat(fd, &info) || !StintRegular(info, owner)) goto finish;
  {
    NSData *before = StintReadFD(fd, 2*1024*1024);
    if (!before) goto finish;
    NSData *after = StintHostsData(before, domains, error);
    if (!after) goto finish;
    if ([before isEqualToData:after]) { okay = YES; goto finish; }
    // Do not copy immutable/append-only flags onto a temporary replacement.
    if (info.st_flags & (UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND)) {
      if (error) *error = StintFileError(@"The hosts file is locked or append-only. Stint kept it unchanged.");
      goto finish;
    }
    tempName = [@".stint-hosts-" stringByAppendingString:NSUUID.UUID.UUIDString];
    temporary = openat(directory, tempName.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (temporary < 0 || !StintWriteFD(temporary, after)) goto finish;
    if (fcopyfile(fd, temporary, NULL, COPYFILE_METADATA) || fchown(temporary, info.st_uid, info.st_gid) || fchmod(temporary, info.st_mode & 0777) || fsync(temporary)) goto finish;
    struct stat current;
    int check = openat(directory, path.lastPathComponent.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    BOOL unchanged = check >= 0 && !fstat(check, &current) && current.st_dev == info.st_dev && current.st_ino == info.st_ino && StintRegular(current, owner) && [StintReadFD(check, 2*1024*1024) isEqualToData:before];
    if (check >= 0) close(check);
    if (!unchanged || renameat(directory, tempName.UTF8String, directory, path.lastPathComponent.fileSystemRepresentation)) goto finish;
    (void)fsync(directory);
    if (changed) *changed = YES;
    okay = YES;
  }
finish:
  if (temporary >= 0) close(temporary);
  if (tempName && !okay) unlinkat(directory, tempName.UTF8String, 0);
  if (fd >= 0) close(fd);
  close(directory);
  if (!okay && error && !*error) *error = StintFileError(@"Hosts update failed or the file changed. Stint will retry; other entries were not intentionally changed.");
  return okay;
}
