#import "StintLocalProxy.h"
#import "../HostsBlocker/StintBlockerPolicy.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

enum { StintConnectionLimit = 128, StintHealthAllowance = 8,
       StintDescriptorLimit = 2 + 2 * (StintConnectionLimit + StintHealthAllowance) };
static const NSUInteger StintHeaderLimit = 16 * 1024;
static const NSUInteger StintBufferLimit = 64 * 1024;
static const unsigned long long StintBodyLimit = 64ULL * 1024 * 1024;
static double StintNow(void) { return NSProcessInfo.processInfo.systemUptime; }
static double StintWall(void) { return NSDate.date.timeIntervalSince1970 * 1000; }

static BOOL StintConfigureSocket(int fd) {
  int flags = fcntl(fd, F_GETFL, 0), yes = 1;
  return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 &&
    fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 &&
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)) == 0;
}
static BOOL StintWouldBlock(void) { return errno == EAGAIN || errno == EWOULDBLOCK; }
static BOOL StintToken(NSString *value) {
  if (!value.length) return NO;
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
    @"!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
  return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

// Parse an authority without URL-decoder ambiguities, userinfo, or zone identifiers.
static BOOL StintAuthority(NSString *text, uint16_t fallback, NSString **hostOut, uint16_t *portOut) {
  if (!text.length || text.length > 300) return NO;
  NSString *host, *portString = nil;
  if ([text hasPrefix:@"["]) {
    NSRange end = [text rangeOfString:@"]"];
    if (end.location == NSNotFound || end.location < 2) return NO;
    host = [text substringWithRange:NSMakeRange(1, end.location - 1)];
    struct in6_addr address;
    if (inet_pton(AF_INET6, host.UTF8String, &address) != 1) return NO;
    char normalized[INET6_ADDRSTRLEN];
    if (!inet_ntop(AF_INET6, &address, normalized, sizeof(normalized))) return NO;
    host = [NSString stringWithUTF8String:normalized];
    NSString *tail = [text substringFromIndex:NSMaxRange(end)];
    if (tail.length) {
      if (![tail hasPrefix:@":"]) return NO;
      portString = [tail substringFromIndex:1];
    }
  } else {
    NSArray *pieces = [text componentsSeparatedByString:@":"];
    if (pieces.count > 2) return NO;
    host = [pieces[0] lowercaseString];
    if (pieces.count == 2) portString = pieces[1];
    if ([host hasSuffix:@"."]) host = [host substringToIndex:host.length - 1];
    if (!host.length || host.length > 253) return NO;
    struct in_addr address;
    if (inet_pton(AF_INET, host.UTF8String, &address) != 1) {
      // Reject noncanonical all-decimal IPv4 forms instead of guessing labels.
      if ([host rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789."].invertedSet].location == NSNotFound) return NO;
      for (NSString *label in [host componentsSeparatedByString:@"."]) {
        if (!label.length || label.length > 63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"] ||
            [label rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"].invertedSet].location != NSNotFound) return NO;
      }
    }
  }
  unsigned long port = fallback;
  if (portString != nil) {
    if (!portString.length || portString.length > 5 ||
        [portString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return NO;
    port = strtoul(portString.UTF8String, NULL, 10);
  }
  if (!port || port > UINT16_MAX) return NO;
  *hostOut = host;
  *portOut = (uint16_t)port;
  return YES;
}

typedef NS_ENUM(NSUInteger, StintPhase) { StintHeaders, StintResolving, StintConnecting, StintRelay, StintReply };
@interface StintProxySession : NSObject
@property(nonatomic) uint64_t identifier;
@property(nonatomic) int client;
@property(nonatomic) int upstream;
@property(nonatomic) StintPhase phase;
@property(nonatomic) double deadline;
@property(nonatomic) double activity;
@property(nonatomic, copy) NSString *host;
@property(nonatomic) uint16_t targetPort;
@property(nonatomic) BOOL tunnel;
@property(nonatomic) BOOL clientEOF;
@property(nonatomic) BOOL upstreamEOF;
@property(nonatomic) BOOL upstreamWriteClosed;
@property(nonatomic) BOOL clientWriteClosed;
@property(nonatomic) unsigned long long bodyRemaining;
@property(nonatomic, strong) NSMutableData *headers;
@property(nonatomic, strong) NSMutableData *toUpstream;
@property(nonatomic, strong) NSMutableData *toClient;
@property(nonatomic, copy) NSArray<NSData *> *addresses;
@property(nonatomic) NSUInteger addressIndex;
@property(nonatomic) BOOL resolutionStarted;
@property(nonatomic) BOOL healthOnly;
@end
@implementation StintProxySession
- (instancetype)init {
  if ((self = [super init])) {
    _client = _upstream = -1;
    _headers = [NSMutableData data]; _toUpstream = [NSMutableData data]; _toClient = [NSMutableData data];
    _activity = StintNow(); _deadline = _activity + 10;
  }
  return self;
}
- (void)dealloc { if (_client >= 0) close(_client); if (_upstream >= 0) close(_upstream); }
@end

// Only the event loop owns session descriptors. Other threads publish state and
// wake it while holding lock, including during descriptor teardown.
@interface StintProxyCore : NSObject {
@public
  NSLock *_lock;
  uint16_t _requestedPort, _port;
  NSString *_token;
  int _listener, _wakeRead, _wakeWrite;
  BOOL _running, _stopping;
  uint64_t _generation, _nextIdentifier;
  NSUInteger _resolverCount;
  dispatch_group_t _loopGroup;
  StintBlockerPolicy *_policy;
  NSData *_lastPolicyData;
  NSMutableArray<NSDictionary *> *_resolutions;
  NSMutableDictionary<NSNumber *, StintProxySession *> *_sessions;
}
- (instancetype)initWithPort:(uint16_t)port;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (void)updatePolicy:(NSDictionary *)policy;
- (void)run;
@end

@implementation StintProxyCore
- (instancetype)initWithPort:(uint16_t)port {
  if ((self = [super init])) {
    _lock = [NSLock new]; _requestedPort = port; _port = port;
    _listener = _wakeRead = _wakeWrite = -1;
    _token = [[[NSUUID.UUID.UUIDString stringByAppendingString:NSUUID.UUID.UUIDString]
      stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    _loopGroup = dispatch_group_create();
    _resolutions = [NSMutableArray array];
    _sessions = [NSMutableDictionary dictionary];
    _policy = [StintBlockerPolicy policyWithDictionary:nil now:StintWall() uptime:StintNow()];
  }
  return self;
}
- (void)wakeLocked {
  if (_wakeWrite >= 0) { uint8_t byte = 1; (void)send(_wakeWrite, &byte, 1, 0); }
}
- (BOOL)start:(NSError **)error {
  [_lock lock];
  if (_running) {
    BOOL ready = !_stopping; [_lock unlock];
    if (!ready && error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EBUSY userInfo:nil];
    return ready;
  }
  int listener = socket(AF_INET, SOCK_STREAM, 0), wake[2] = {-1, -1};
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons(_requestedPort);
  int yes = 1;
  if (listener < 0 || !StintConfigureSocket(listener) ||
      setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) != 0 ||
      bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 128) != 0 ||
      socketpair(AF_UNIX, SOCK_STREAM, 0, wake) != 0 || !StintConfigureSocket(wake[0]) || !StintConfigureSocket(wake[1])) {
    int saved = errno;
    if (listener >= 0) close(listener);
    if (wake[0] >= 0) close(wake[0]); if (wake[1] >= 0) close(wake[1]);
    [_lock unlock];
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:saved userInfo:nil];
    return NO;
  }
  socklen_t length = sizeof(address);
  if (getsockname(listener, (struct sockaddr *)&address, &length) != 0) {
    int saved = errno; close(listener); close(wake[0]); close(wake[1]); [_lock unlock];
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:saved userInfo:nil];
    return NO;
  }
  _listener = listener; _wakeRead = wake[0]; _wakeWrite = wake[1];
  _port = ntohs(address.sin_port); _generation++; _running = YES; _stopping = NO;
  _loopGroup = dispatch_group_create();
  dispatch_group_enter(_loopGroup);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self run]; });
  [_lock unlock]; return YES;
}
- (void)stop {
  [_lock lock]; BOOL wait = _running; dispatch_group_t group = _loopGroup;
  if (wait) { _stopping = YES; [self wakeLocked]; }
  [_lock unlock];
  if (wait) dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}
- (void)updatePolicy:(NSDictionary *)policy {
  [_lock lock];
  // A canonical serialized snapshot distinguishes JSON booleans from numbers,
  // and prevents caller mutation or identical heartbeats from renewing a lease.
  NSData *data = [NSJSONSerialization isValidJSONObject:policy] ? [NSJSONSerialization dataWithJSONObject:policy options:NSJSONWritingSortedKeys error:NULL] : nil;
  if (![_lastPolicyData isEqual:data]) {
    NSDictionary *snapshot = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    _lastPolicyData = data;
    _policy = [StintBlockerPolicy policyWithDictionary:snapshot now:StintWall() uptime:StintNow()];
    [self wakeLocked];
  }
  [_lock unlock];
}
- (BOOL)blocked:(NSString *)host {
  if (!host) return NO;
  [_lock lock]; StintBlockerPolicy *policy = _policy; [_lock unlock];
  if (![policy isEffectiveAt:StintWall() uptime:StintNow()]) return NO;
  for (NSString *domain in policy.domains) {
    if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
  }
  return NO;
}
- (void)remove:(StintProxySession *)session {
  // Close now, never in a DNS completion or a later object release.
  if (session.client >= 0) { close(session.client); session.client = -1; }
  if (session.upstream >= 0) { close(session.upstream); session.upstream = -1; }
  [_sessions removeObjectForKey:@(session.identifier)];
}
- (void)reply:(NSInteger)status session:(StintProxySession *)session body:(NSString *)body {
  if (session.upstream >= 0) { close(session.upstream); session.upstream = -1; }
  NSString *reason = @{@200:@"OK", @400:@"Bad Request", @403:@"Forbidden", @408:@"Request Timeout", @431:@"Request Header Fields Too Large", @502:@"Bad Gateway", @503:@"Service Unavailable", @504:@"Gateway Timeout"}[@(status)] ?: @"Error";
  NSData *payload = [body dataUsingEncoding:NSUTF8StringEncoding];
  NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Length: %lu\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n", (long)status, reason, (unsigned long)payload.length];
  [session.toClient setData:[head dataUsingEncoding:NSASCIIStringEncoding]];
  [session.toClient appendData:payload]; [session.toUpstream setLength:0]; [session.headers setLength:0];
  session.phase = StintReply; session.deadline = StintNow() + 10;
}
- (void)resolve:(StintProxySession *)session {
  if ([self blocked:session.host]) { [self reply:403 session:session body:@"Blocked during focus\n"]; return; }
  if (session.phase != StintResolving) {
    session.phase = StintResolving; session.deadline = StintNow() + 10;
  }
  [_lock lock];
  // Pending requests occupy existing bounded session slots. Do not create a
  // dispatch task for each waiting client, or reject normal bursts of tabs.
  if (_resolverCount >= 4 || _stopping) { [_lock unlock]; return; }
  _resolverCount++;
  session.resolutionStarted = YES;
  uint64_t generation = _generation, identifier = session.identifier;
  [_lock unlock];
  NSString *host = session.host;
  uint16_t port = session.targetPort;
  __weak StintProxyCore *weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    @autoreleasepool {
      NSString *lookupHost = host;
      uint16_t lookupPort = port;
#ifdef STINT_PROXY_TESTING
      // Compiled only into the isolated native test binary, never the app.
      if ([host isEqualToString:@"fixture.test"] || [host hasSuffix:@".fixture.test"]) {
        lookupHost = @"127.0.0.1";
        const char *delay = getenv("STINT_PROXY_TEST_DNS_DELAY_MS");
        if (delay) usleep((useconds_t)MIN(strtoul(delay, NULL, 10), 1000UL) * 1000);
        const char *configured = getenv(port == 80 ? "STINT_PROXY_TEST_HTTP_PORT" : "STINT_PROXY_TEST_TLS_PORT");
        if (configured) { unsigned long value = strtoul(configured, NULL, 10); if (value > 0 && value <= UINT16_MAX) lookupPort = (uint16_t)value; }
      }
#endif
      struct addrinfo hints = {0}, *result = NULL;
      hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC; hints.ai_protocol = IPPROTO_TCP;
      char service[6]; snprintf(service, sizeof(service), "%u", lookupPort);
      NSMutableArray *addresses = [NSMutableArray array];
      if (getaddrinfo(lookupHost.UTF8String, service, &hints, &result) == 0) {
        for (struct addrinfo *entry = result; entry && addresses.count < 16; entry = entry->ai_next) {
          if ((entry->ai_family == AF_INET && entry->ai_addrlen == sizeof(struct sockaddr_in)) ||
              (entry->ai_family == AF_INET6 && entry->ai_addrlen == sizeof(struct sockaddr_in6)))
            [addresses addObject:[NSData dataWithBytes:entry->ai_addr length:entry->ai_addrlen]];
        }
        freeaddrinfo(result);
      }
      StintProxyCore *core = weakSelf;
      if (core) {
        [core->_lock lock]; core->_resolverCount--;
        if (core->_running && !core->_stopping && core->_generation == generation) {
          [core->_resolutions addObject:@{@"id":@(identifier), @"addresses":addresses}];
          [core wakeLocked];
        }
        [core->_lock unlock];
      }
    }
  });
}
- (BOOL)parse:(StintProxySession *)session headerLength:(NSUInteger)length {
  const uint8_t *bytes = session.headers.bytes;
  for (NSUInteger i = 0; i < length; i++) {
    if ((bytes[i] < 32 && bytes[i] != '\r' && bytes[i] != '\n') || bytes[i] > 126 ||
        (bytes[i] == '\r' && (i + 1 >= length || bytes[i + 1] != '\n')) ||
        (bytes[i] == '\n' && (!i || bytes[i - 1] != '\r'))) return NO;
  }
  NSString *text = [[NSString alloc] initWithBytes:bytes length:length - 4 encoding:NSASCIIStringEncoding];
  NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\r\n"];
  NSArray<NSString *> *request = [lines[0] componentsSeparatedByString:@" "];
  if (request.count != 3 || !StintToken(request[0]) || !request[1].length ||
      !([request[2] isEqualToString:@"HTTP/1.1"] || [request[2] isEqualToString:@"HTTP/1.0"])) return NO;
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  for (NSUInteger i = 1; i < lines.count; i++) {
    NSString *line = lines[i]; NSRange colon = [line rangeOfString:@":"];
    if (colon.location == NSNotFound) return NO;
    NSString *name = [[line substringToIndex:colon.location] lowercaseString];
    if (!StintToken(name) || headers[name]) return NO;
    NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]];
    if ([value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) return NO;
    headers[name] = value; [names addObject:name];
  }
  if (headers[@"transfer-encoding"] || headers[@"upgrade"] || headers[@"expect"] || headers[@"trailer"]) return NO;
  NSMutableSet *connectionFields = [NSMutableSet set];
  for (NSString *value in [headers[@"connection"] componentsSeparatedByString:@","]) {
    NSString *name = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
    if (!StintToken(name) || [name isEqualToString:@"upgrade"] || [name isEqualToString:@"host"] || [name isEqualToString:@"content-length"]) return NO;
    [connectionFields addObject:name];
  }
  unsigned long long body = 0;
  if (headers[@"content-length"]) {
    NSString *value = headers[@"content-length"];
    if (!value.length || value.length > 10 || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return NO;
    body = strtoull(value.UTF8String, NULL, 10);
    if (body > StintBodyLimit) return NO;
  }
  NSUInteger extraLength = session.headers.length - length;
  if ([request[0] isEqualToString:@"GET"] && [request[1] isEqualToString:@"/_stint_health"] && [request[2] isEqualToString:@"HTTP/1.1"]) {
    if (body || extraLength) return NO;
    BOOL authenticated = [headers[@"x-stint-token"] isEqualToString:_token];
    [self reply:authenticated ? 200 : 403 session:session body:authenticated ? _token : @""];
    return YES;
  }
  if (session.healthOnly) { [self reply:503 session:session body:@""]; return YES; }
  BOOL tunnel = [request[0] isEqualToString:@"CONNECT"];
  NSString *host = nil, *origin = nil; uint16_t port = 0;
  if (tunnel) {
    if (body || !StintAuthority(request[1], 0, &host, &port) || port != 443) return NO;
  } else {
    NSString *target = request[1];
    if (target.length < 8 || [[target substringToIndex:7] caseInsensitiveCompare:@"http://"] != NSOrderedSame || [target containsString:@"#"]) return NO;
    NSString *rest = [target substringFromIndex:7];
    NSRange delimiter = [rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?"]];
    NSString *authority = delimiter.location == NSNotFound ? rest : [rest substringToIndex:delimiter.location];
    origin = delimiter.location == NSNotFound ? @"/" : [rest substringFromIndex:delimiter.location];
    if ([origin hasPrefix:@"?"]) origin = [@"/" stringByAppendingString:origin];
    if (!StintAuthority(authority, 80, &host, &port) || port != 80 || !headers[@"host"] || extraLength > body) return NO;
  }
  if (headers[@"host"]) {
    NSString *headerHost = nil; uint16_t headerPort = 0;
    if (!StintAuthority(headers[@"host"], tunnel ? 443 : 80, &headerHost, &headerPort) || ![headerHost isEqualToString:host] || headerPort != port) return NO;
  }
  session.host = host; session.targetPort = port; session.tunnel = tunnel; session.bodyRemaining = body;
  if ([self blocked:host]) { [self reply:403 session:session body:@"Blocked during focus\n"]; return YES; }
  if (!tunnel) {
    NSMutableString *forward = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", request[0], origin];
    NSSet *hop = [NSSet setWithArray:@[@"connection", @"proxy-connection", @"proxy-authorization", @"keep-alive", @"te", @"x-stint-token"]];
    for (NSString *name in names) {
      if (![hop containsObject:name] && ![connectionFields containsObject:name]) [forward appendFormat:@"%@: %@\r\n", name, headers[name]];
    }
    [forward appendString:@"Connection: close\r\n\r\n"];
    [session.toUpstream appendData:[forward dataUsingEncoding:NSASCIIStringEncoding]];
    session.bodyRemaining -= extraLength;
  }
  if (extraLength) [session.toUpstream appendBytes:bytes + length length:extraLength];
  [session.headers setLength:0];
  [self resolve:session]; return YES;
}
- (void)readHeaders:(StintProxySession *)session {
  uint8_t buffer[4096]; ssize_t count = recv(session.client, buffer, sizeof(buffer), 0);
  if (count == 0 || (count < 0 && !StintWouldBlock() && errno != EINTR)) { [self remove:session]; return; }
  if (count < 0) return;
  [session.headers appendBytes:buffer length:(NSUInteger)count];
  const char marker[] = "\r\n\r\n";
  NSRange end = [session.headers rangeOfData:[NSData dataWithBytes:marker length:4] options:0 range:NSMakeRange(0, session.headers.length)];
  if (end.location != NSNotFound) {
    NSUInteger length = NSMaxRange(end);
    if (length > StintHeaderLimit) [self reply:431 session:session body:@""];
    else if (![self parse:session headerLength:length]) [self reply:400 session:session body:@""];
  } else if (session.headers.length >= StintHeaderLimit) [self reply:431 session:session body:@""];
}
- (void)connected:(StintProxySession *)session {
  if ([self blocked:session.host]) { [self reply:403 session:session body:@"Blocked during focus\n"]; return; }
  session.phase = StintRelay; session.activity = StintNow();
  if (session.tunnel) [session.toClient appendData:[@"HTTP/1.1 200 Connection Established\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding]];
}
- (void)tryAddress:(StintProxySession *)session {
  if (session.upstream >= 0) { close(session.upstream); session.upstream = -1; }
  while (session.addressIndex < session.addresses.count) {
    NSData *data = session.addresses[session.addressIndex++]; const struct sockaddr *address = data.bytes;
    int fd = socket(address->sa_family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) continue;
    if (!StintConfigureSocket(fd)) { close(fd); continue; }
    session.upstream = fd;
    int result = connect(fd, address, (socklen_t)data.length);
    if (result == 0) { [self connected:session]; return; }
    if (errno == EINPROGRESS) { session.phase = StintConnecting; return; }
    close(fd); session.upstream = -1;
  }
  [self reply:502 session:session body:@""];
}
- (void)writeBuffer:(NSMutableData *)data fd:(int)fd session:(StintProxySession *)session {
  if (!data.length) return;
  ssize_t count = send(fd, data.bytes, data.length, 0);
  if (count > 0) { [data replaceBytesInRange:NSMakeRange(0, (NSUInteger)count) withBytes:NULL length:0]; session.activity = StintNow(); }
  else if (count == 0 || (!StintWouldBlock() && errno != EINTR)) [self remove:session];
}
- (void)readRelay:(StintProxySession *)session fromClient:(BOOL)client {
  NSMutableData *buffer = client ? session.toUpstream : session.toClient;
  NSUInteger available = StintBufferLimit - buffer.length;
  if (!available) return;
  uint8_t bytes[16384]; NSUInteger capacity = MIN(available, sizeof(bytes));
  // Once the one HTTP body is complete, any further byte is a second request.
  BOOL excessHTTP = client && !session.tunnel && !session.bodyRemaining;
  if (client && !session.tunnel) capacity = excessHTTP ? 1 : (NSUInteger)MIN((unsigned long long)capacity, session.bodyRemaining);
  ssize_t count = recv(client ? session.client : session.upstream, bytes, capacity, 0);
  if (count > 0) {
    if (excessHTTP) { [self remove:session]; return; }
    [buffer appendBytes:bytes length:(NSUInteger)count]; session.activity = StintNow();
    if (client && !session.tunnel) session.bodyRemaining -= (NSUInteger)count;
  } else if (count == 0) {
    if (client) {
      if (!session.tunnel && session.bodyRemaining) { [self remove:session]; return; }
      session.clientEOF = YES;
    } else session.upstreamEOF = YES;
  } else if (!StintWouldBlock() && errno != EINTR) [self remove:session];
}
- (void)finishRelay:(StintProxySession *)session {
  if (session.client < 0) return;
  BOOL requestDone = session.clientEOF || (!session.tunnel && !session.bodyRemaining);
  if (requestDone && !session.toUpstream.length && !session.upstreamWriteClosed) {
    shutdown(session.upstream, SHUT_WR); session.upstreamWriteClosed = YES;
  }
  if (session.upstreamEOF && !session.toClient.length && !session.clientWriteClosed) {
    shutdown(session.client, SHUT_WR); session.clientWriteClosed = YES;
  }
  if ((session.upstreamEOF && !session.toClient.length && !session.tunnel) ||
      (session.upstreamEOF && session.clientEOF && !session.toClient.length && !session.toUpstream.length)) [self remove:session];
}
- (void)acceptClients {
  // Bound work per turn so connection floods cannot starve relay or stop.
  NSUInteger normalCount = 0;
  for (StintProxySession *session in _sessions.allValues) if (!session.healthOnly) normalCount++;
  for (NSUInteger i = 0; i < 32; i++) {
    int fd = accept(_listener, NULL, NULL);
    if (fd < 0) break;
    if (!StintConfigureSocket(fd)) { close(fd); continue; }
    if (_sessions.count >= StintConnectionLimit + StintHealthAllowance) {
      static const char busy[] = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
      (void)send(fd, busy, sizeof(busy) - 1, 0); close(fd); continue;
    }
    StintProxySession *session = [StintProxySession new];
    // Browser load must not make the helper mistake a healthy proxy for a dead
    // one and release protection. Reserved slots never open upstream sockets.
    session.healthOnly = normalCount >= StintConnectionLimit;
    if (session.healthOnly) session.deadline = StintNow() + 1;
    else normalCount++;
    session.client = fd; session.identifier = ++_nextIdentifier; _sessions[@(session.identifier)] = session;
  }
}
- (void)run {
  for (;;) {
    @autoreleasepool {
      [_lock lock]; BOOL stopping = _stopping;
      NSArray *resolutions = [_resolutions copy]; [_resolutions removeAllObjects]; [_lock unlock];
      if (stopping) break;
      for (NSDictionary *resolution in resolutions) {
        StintProxySession *session = _sessions[resolution[@"id"]];
        if (session && session.phase == StintResolving) {
          if ([self blocked:session.host]) [self reply:403 session:session body:@"Blocked during focus\n"];
          else if (StintNow() >= session.deadline) [self reply:504 session:session body:@""];
          else { session.addresses = resolution[@"addresses"]; [self tryAddress:session]; }
        }
      }
      double now = StintNow();
      for (StintProxySession *session in [_sessions.allValues copy]) {
        if ([self blocked:session.host] && session.phase != StintReply) {
          if (session.phase == StintRelay) [self remove:session];
          else [self reply:403 session:session body:@"Blocked during focus\n"];
        } else if (session.phase == StintRelay ? now - session.activity >= 300 : now >= session.deadline) {
          if (session.phase == StintHeaders) [self reply:408 session:session body:@""];
          else if (session.phase == StintConnecting || session.phase == StintResolving) [self reply:504 session:session body:@""];
          else [self remove:session];
        }
      }
      for (StintProxySession *session in _sessions.allValues) {
        if (session.phase == StintResolving && !session.resolutionStarted) [self resolve:session];
      }
      struct pollfd descriptors[StintDescriptorLimit];
      StintProxySession *__strong owners[StintDescriptorLimit] = {nil};
      BOOL upstreams[StintDescriptorLimit] = {NO};
      nfds_t count = 2;
      descriptors[0] = (struct pollfd){_wakeRead, POLLIN, 0};
      descriptors[1] = (struct pollfd){_listener, POLLIN, 0};
      for (StintProxySession *session in _sessions.allValues) {
        short clientEvents = 0, upstreamEvents = 0;
        if (session.phase == StintHeaders) clientEvents = POLLIN;
        else if (session.phase == StintReply) clientEvents = POLLOUT;
        else if (session.phase == StintRelay) {
          if (!session.clientEOF && session.toUpstream.length < StintBufferLimit) clientEvents |= POLLIN;
          if (session.toClient.length) clientEvents |= POLLOUT;
          if (!session.upstreamEOF && session.toClient.length < StintBufferLimit) upstreamEvents |= POLLIN;
          if (session.toUpstream.length) upstreamEvents |= POLLOUT;
        } else if (session.phase == StintConnecting) upstreamEvents = POLLOUT;
        if (clientEvents) { descriptors[count] = (struct pollfd){session.client, clientEvents, 0}; owners[count++] = session; }
        if (upstreamEvents) { descriptors[count] = (struct pollfd){session.upstream, upstreamEvents, 0}; upstreams[count] = YES; owners[count++] = session; }
      }
      int ready = poll(descriptors, count, 200);
      if (ready < 0) { if (errno == EINTR) continue; break; }
      if (descriptors[0].revents & POLLIN) { uint8_t bytes[256]; while (recv(_wakeRead, bytes, sizeof(bytes), 0) > 0) {} continue; }
      if (descriptors[0].revents & (POLLERR | POLLNVAL | POLLHUP)) break;
      if (descriptors[1].revents & (POLLERR | POLLNVAL | POLLHUP)) break;
      if (descriptors[1].revents & POLLIN) [self acceptClients];
      for (nfds_t i = 2; i < count; i++) {
        short events = descriptors[i].revents; StintProxySession *session = owners[i]; BOOL upstream = upstreams[i];
        if (!events || session.client < 0 || (upstream && session.upstream != descriptors[i].fd)) continue;
        if (events & POLLNVAL) { [self remove:session]; continue; }
        if (session.phase == StintConnecting && upstream) {
          int failure = 0; socklen_t length = sizeof(failure);
          if (getsockopt(session.upstream, SOL_SOCKET, SO_ERROR, &failure, &length) != 0 || failure) [self tryAddress:session];
          else [self connected:session];
          continue;
        }
        if (events & POLLERR) { [self remove:session]; continue; }
        if (session.phase == StintHeaders) { if (events & (POLLIN | POLLHUP)) [self readHeaders:session]; }
        else if (session.phase == StintReply) {
          if (events & POLLOUT) [self writeBuffer:session.toClient fd:session.client session:session];
          if (session.client >= 0 && (!session.toClient.length || (events & POLLHUP))) [self remove:session];
        } else if (session.phase == StintRelay) {
          if (events & POLLOUT) [self writeBuffer:upstream ? session.toUpstream : session.toClient fd:descriptors[i].fd session:session];
          if (session.client >= 0 && (events & (POLLIN | POLLHUP))) [self readRelay:session fromClient:!upstream];
          [self finishRelay:session];
        }
      }
    }
  }
  [_lock lock];
  for (StintProxySession *session in [_sessions.allValues copy]) [self remove:session];
  close(_listener); close(_wakeRead); close(_wakeWrite);
  _listener = _wakeRead = _wakeWrite = -1; _running = NO; _stopping = NO;
  [_resolutions removeAllObjects];
  dispatch_group_leave(_loopGroup);
  [_lock unlock];
}
@end

@interface StintLocalProxy ()
@property(nonatomic, strong) StintProxyCore *core;
@end
@implementation StintLocalProxy
- (instancetype)initWithPort:(uint16_t)port { if ((self = [super init])) _core = [[StintProxyCore alloc] initWithPort:port]; return self; }
- (uint16_t)port { [_core->_lock lock]; uint16_t value = _core->_port; [_core->_lock unlock]; return value; }
- (NSString *)token { return _core->_token; }
- (BOOL)running { [_core->_lock lock]; BOOL value = _core->_running && !_core->_stopping; [_core->_lock unlock]; return value; }
- (BOOL)start:(NSError **)error { return [_core start:error]; }
- (void)stop { [_core stop]; }
- (void)updatePolicy:(NSDictionary *)policy { [_core updatePolicy:policy]; }
- (void)dealloc { [_core stop]; }
@end
