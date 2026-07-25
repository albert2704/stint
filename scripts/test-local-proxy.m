#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import <errno.h>
#import <poll.h>
#import <signal.h>
#import <sys/socket.h>
#import <unistd.h>
#import "../macos/ProxyBlocker/StintLocalProxy.h"

// These fixtures use ephemeral loopback ports, never change network preferences,
// and do not require DNS or internet access. The tunnel fixture echoes opaque
// binary bytes; it deliberately does not terminate or inspect TLS.
static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
  if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
  checks++;
}
static NSData *Bytes(NSString *value) { return [value dataUsingEncoding:NSUTF8StringEncoding]; }
static double Now(void) { return NSDate.date.timeIntervalSince1970 * 1000; }
static void ConfigureSocket(int fd) {
  int yes = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
  struct timeval timeout = {.tv_sec = 5, .tv_usec = 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
}
static BOOL WriteAll(int fd, NSData *data) {
  const uint8_t *bytes = data.bytes; NSUInteger offset = 0;
  while (offset < data.length) {
    ssize_t n = send(fd, bytes + offset, data.length - offset, 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return NO;
    offset += (NSUInteger)n;
  }
  return YES;
}
static NSData *ReadCount(int fd, NSUInteger count) {
  NSMutableData *data = [NSMutableData data];
  uint8_t buffer[8192];
  while (data.length < count) {
    ssize_t n = recv(fd, buffer, MIN(sizeof(buffer), count - data.length), 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    [data appendBytes:buffer length:(NSUInteger)n];
  }
  return data;
}
static NSData *ReadToClose(int fd) {
  NSMutableData *data = [NSMutableData data]; uint8_t buffer[8192];
  while (data.length < 2 * 1024 * 1024) {
    ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    [data appendBytes:buffer length:(NSUInteger)n];
  }
  return data;
}
static NSData *ReadHeaders(int fd) {
  NSMutableData *data = [NSMutableData data];
  NSData *end = Bytes(@"\r\n\r\n");
  while (data.length < 32768) {
    uint8_t byte; ssize_t n = recv(fd, &byte, 1, 0);
    if (n < 0 && errno == EINTR) continue;
    if (n != 1) break;
    [data appendBytes:&byte length:1];
    if (data.length >= 4 && [data rangeOfData:end options:0 range:NSMakeRange(data.length-4,4)].location != NSNotFound) break;
  }
  return data;
}
static NSInteger Status(NSData *data) {
  NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
  NSArray *parts = [[text componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];
  return parts.count > 1 ? [parts[1] integerValue] : 0;
}
static int Dial(uint16_t port) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  ConfigureSocket(fd);
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET; address.sin_port = htons(port); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) { close(fd); return -1; }
  return fd;
}
static NSData *Exchange(uint16_t port, NSData *request) {
  int fd = Dial(port); Check(fd >= 0, @"connect to local proxy");
  Check(WriteAll(fd, request), @"write complete proxy request");
  NSData *response = ReadToClose(fd); close(fd); return response;
}
static NSString *HTTP(NSString *host) {
  return [NSString stringWithFormat:@"GET http://%@/resource?q=one HTTP/1.1\r\nHost: %@\r\n\r\n", host, host];
}
static NSString *CONNECT(NSString *host) {
  return [NSString stringWithFormat:@"CONNECT %@:443 HTTP/1.1\r\nHost: %@:443\r\n\r\n", host, host];
}
static NSData *TunnelTail(void) {
  const uint8_t tail[] = {0x00, 0xff, 0x54, 0x41, 0x49, 0x4c};
  return [NSData dataWithBytes:tail length:sizeof(tail)];
}

@interface Fixture : NSObject
@property(nonatomic) int listener;
@property(nonatomic) uint16_t port;
@property(nonatomic) BOOL tunnel;
@property(nonatomic) BOOL running;
@property(nonatomic) NSUInteger acceptedConnections;
@property(nonatomic, strong) NSMutableArray<NSData *> *requests;
@property(nonatomic, strong) dispatch_group_t workers;
- (instancetype)initTunnel:(BOOL)tunnel;
- (NSUInteger)requestCount;
- (NSUInteger)acceptCount;
- (NSData *)lastRequest;
- (void)stop;
@end
@implementation Fixture
- (instancetype)initTunnel:(BOOL)tunnel {
  if (!(self = [super init])) return nil;
  self.tunnel = tunnel; self.requests = [NSMutableArray array]; self.workers = dispatch_group_create();
  self.listener = socket(AF_INET, SOCK_STREAM, 0); Check(self.listener >= 0, @"create fixture socket");
  ConfigureSocket(self.listener);
  struct sockaddr_in address = {0}; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int bindResult = bind(self.listener, (struct sockaddr *)&address, sizeof(address));
  Check(bindResult == 0, [NSString stringWithFormat:@"bind unprivileged fixture: %s", strerror(errno)]);
  socklen_t length = sizeof(address);
  Check(getsockname(self.listener, (struct sockaddr *)&address, &length) == 0, @"read fixture port");
  self.port = ntohs(address.sin_port);
  Check(listen(self.listener, 128) == 0, @"listen fixture");
  self.running = YES;
  dispatch_group_async(self.workers, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    @autoreleasepool {
      for (;;) {
        @synchronized(self) { if (!self.running) break; }
        struct pollfd p = {.fd = self.listener, .events = POLLIN};
        if (poll(&p, 1, 50) <= 0) continue;
        int fd = accept(self.listener, NULL, NULL);
        if (fd < 0) continue;
        @synchronized(self) { self.acceptedConnections++; }
        ConfigureSocket(fd);
        dispatch_group_async(self.workers, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          @autoreleasepool {
            if (self.tunnel) {
              int size = 1024; setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
              uint8_t buffer[4096]; ssize_t n = recv(fd, buffer, 1, 0);
              if (n == 1 && buffer[0] == 0x7e) {
                // A fixture-only command exercises the opposite half close:
                // the upstream finishes sending but still receives client data.
                WriteAll(fd, Bytes(@"upstream-finished")); shutdown(fd, SHUT_WR);
                NSData *received = ReadToClose(fd);
                @synchronized(self) { [self.requests addObject:received]; }
              } else {
                if (n == 1) WriteAll(fd, [NSData dataWithBytes:buffer length:1]);
                while (n > 0 && (n = recv(fd, buffer, sizeof(buffer), 0)) > 0) {
                  if (!WriteAll(fd, [NSData dataWithBytes:buffer length:(NSUInteger)n])) break;
                }
                if (n == 0) WriteAll(fd, TunnelTail());
                shutdown(fd, SHUT_WR);
              }
            } else {
              NSData *header = ReadHeaders(fd);
              NSString *text = [[NSString alloc] initWithData:header encoding:NSISOLatin1StringEncoding];
              NSUInteger bodySize = 0;
              for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
                if ([[line lowercaseString] hasPrefix:@"content-length:"]) bodySize = (NSUInteger)[[line substringFromIndex:15] integerValue];
              }
              if (bodySize <= 1024 * 1024 && header.length) {
                NSData *body = ReadCount(fd, bodySize);
                NSMutableData *request = [header mutableCopy]; [request appendData:body];
                @synchronized(self) { [self.requests addObject:request]; }
                NSMutableData *response = [Bytes([NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)body.length]) mutableCopy];
                [response appendData:body]; WriteAll(fd, response);
              }
            }
            close(fd);
          }
        });
      }
    }
  });
  return self;
}
- (NSUInteger)requestCount { @synchronized(self) { return self.requests.count; } }
- (NSUInteger)acceptCount { @synchronized(self) { return self.acceptedConnections; } }
- (NSData *)lastRequest { @synchronized(self) { return self.requests.lastObject; } }
- (void)stop {
  @synchronized(self) { self.running = NO; }
  Check(dispatch_group_wait(self.workers, dispatch_time(DISPATCH_TIME_NOW, 6*NSEC_PER_SEC)) == 0, @"fixtures stop with bounded workers");
  close(self.listener);
}
@end

static NSDictionary *Policy(StintLocalProxy *proxy, NSArray<NSString *> *domains, double duration) {
  double now = Now();
  return @{@"version":@2, @"active":@YES, @"ownerUID":@(getuid()), @"sessionId":NSUUID.UUID.UUIDString,
    @"domains":domains, @"issuedAtMilliseconds":@(now), @"deadlineMilliseconds":@(now+duration),
    @"leaseExpiresAt":@(now+duration), @"proxyPort":@(proxy.port), @"proxyToken":proxy.token};
}
static int OpenTunnel(StintLocalProxy *proxy, NSString *host) {
  int fd = Dial(proxy.port); Check(fd >= 0, @"connect tunnel client");
  Check(WriteAll(fd, Bytes(CONNECT(host))), @"send tunnel handshake");
  Check(Status(ReadHeaders(fd)) == 200, @"allow CONNECT on 443"); return fd;
}
static BOOL ClosesSoon(int fd) {
  struct pollfd p = {.fd=fd, .events=POLLIN|POLLHUP};
  if (poll(&p, 1, 2000) <= 0) return NO;
  uint8_t byte; ssize_t n = recv(fd, &byte, 1, 0);
  return n == 0 || (n < 0 && errno == ECONNRESET);
}

static NSTask *LaunchFixtureTask(NSString *executable, NSArray<NSString *> *arguments,
                                  NSString *input, NSString *output, NSString *errors) {
  NSFileManager *manager = NSFileManager.defaultManager;
  if (![manager createFileAtPath:output contents:nil attributes:nil] ||
      ![manager createFileAtPath:errors contents:nil attributes:nil]) return nil;
  NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:executable];
  task.arguments = arguments;
  task.standardInput = input ? [NSFileHandle fileHandleForReadingAtPath:input] : NSFileHandle.fileHandleWithNullDevice;
  task.standardOutput = [NSFileHandle fileHandleForWritingAtPath:output];
  task.standardError = [NSFileHandle fileHandleForWritingAtPath:errors];
  return [task launchAndReturnError:NULL] ? task : nil;
}
static BOOL WaitFixtureTask(NSTask *task, double timeout) {
  if (!task) return NO;
  double deadline = NSProcessInfo.processInfo.systemUptime + timeout;
  while (task.running && NSProcessInfo.processInfo.systemUptime < deadline) usleep(10000);
  BOOL completed = !task.running;
  if (!completed) kill(task.processIdentifier, SIGKILL);
  [task waitUntilExit]; return completed;
}
static NSString *FixtureText(NSString *path) {
  return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
}
static void TestTLS(StintLocalProxy *proxy, uint16_t echoPort) {
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"stint-proxy-tls-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  NSString *key = [folder stringByAppendingPathComponent:@"key.pem"], *cert = [folder stringByAppendingPathComponent:@"cert.pem"];
  NSString *serverOutput = [folder stringByAppendingPathComponent:@"server.out"], *serverErrors = [folder stringByAppendingPathComponent:@"server.err"];
  NSString *clientOutput = [folder stringByAppendingPathComponent:@"client.out"], *clientErrors = [folder stringByAppendingPathComponent:@"client.err"];
  NSString *requestFile = [folder stringByAppendingPathComponent:@"request.txt"];
  NSTask *generator = nil, *server = nil, *client = nil;
  BOOL certificateReady = NO, serverReady = NO, clientCompleted = NO, clientSucceeded = NO, responseCorrect = NO, certificateVerified = NO, negotiatedTLS = NO;
  NSString *diagnostic = @"";
  @try {
    do {
      if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]) break;
      generator = LaunchFixtureTask(@"/usr/bin/openssl", @[@"req", @"-x509", @"-newkey", @"rsa:2048", @"-nodes", @"-keyout", key, @"-out", cert, @"-days", @"1", @"-subj", @"/CN=fixture.test"], nil,
        [folder stringByAppendingPathComponent:@"cert.out"], [folder stringByAppendingPathComponent:@"cert.err"]);
      certificateReady = WaitFixtureTask(generator,5) && generator.terminationStatus == 0;
      if (!certificateReady) { diagnostic = FixtureText([folder stringByAppendingPathComponent:@"cert.err"]); break; }
      // LibreSSL s_server on macOS only accepts a port and binds all interfaces.
      // Python's TLS listener keeps this fixture strictly on IPv4 loopback.
      NSString *program = @"import socket,ssl,sys\n"
        "ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)\n"
        "ctx.minimum_version=ssl.TLSVersion.TLSv1_2\n"
        "ctx.load_cert_chain(sys.argv[1],sys.argv[2])\n"
        "listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)\n"
        "listener.bind(('127.0.0.1',0)); listener.listen(1); listener.settimeout(5)\n"
        "print('PORT '+str(listener.getsockname()[1]),flush=True)\n"
        "raw,_=listener.accept(); raw.settimeout(3)\n"
        "with ctx.wrap_socket(raw,server_side=True) as conn:\n"
        " print('TLS '+conn.version(),flush=True)\n"
        " request=b''\n"
        " while b'\\r\\n\\r\\n' not in request and len(request)<32768: request+=conn.recv(4096)\n"
        " assert request.startswith(b'GET /tls-fixture HTTP/1.1\\r\\n')\n"
        " body=b'stint-tls-fixture'\n"
        " conn.sendall(b'HTTP/1.1 200 OK\\r\\nConnection: close\\r\\nContent-Length: '+str(len(body)).encode()+b'\\r\\n\\r\\n'+body)\n"
        " conn.unwrap().close()\n"
        "listener.close()\n";
      server = LaunchFixtureTask(@"/usr/bin/env", @[@"python3", @"-c", program, cert, key], nil, serverOutput, serverErrors);
      uint16_t tlsPort = 0;
      for (NSUInteger retry=0; server && retry<200; retry++) {
        NSString *announcement = FixtureText(serverOutput);
        if ([announcement hasPrefix:@"PORT "]) { tlsPort = (uint16_t)[[announcement substringFromIndex:5] intValue]; break; }
        if (!server.running) break;
        usleep(10000);
      }
      serverReady = tlsPort > 0;
      if (!serverReady) { diagnostic = FixtureText(serverErrors); break; }
      setenv("STINT_PROXY_TEST_TLS_PORT", [[NSString stringWithFormat:@"%u", tlsPort] UTF8String],1);
      [Bytes(@"GET /tls-fixture HTTP/1.1\r\nHost: fixture.test\r\nConnection: close\r\n\r\n") writeToFile:requestFile atomically:YES];
      client = LaunchFixtureTask(@"/usr/bin/openssl", @[@"s_client", @"-proxy", [NSString stringWithFormat:@"127.0.0.1:%u",proxy.port], @"-connect", @"fixture.test:443", @"-servername", @"fixture.test", @"-CAfile", cert, @"-verify_return_error", @"-quiet"], requestFile, clientOutput, clientErrors);
      clientCompleted = WaitFixtureTask(client,5); clientSucceeded = clientCompleted && client.terminationStatus == 0;
      NSString *output = FixtureText(clientOutput); diagnostic = FixtureText(clientErrors);
      responseCorrect = [output hasPrefix:@"HTTP/1.1 200 OK\r\n"] && [output hasSuffix:@"stint-tls-fixture"];
      certificateVerified = [diagnostic containsString:@"verify return:1"];
      negotiatedTLS = [FixtureText(serverOutput) containsString:@"TLS TLSv1."];
    } while (NO);
  } @catch (NSException *exception) {
    diagnostic = exception.reason ?: @"TLS fixture exception";
  } @finally {
    // All child processes and temporary credentials are cleaned before an
    // assertion can terminate the test process.
    for (NSTask *task in @[generator ?: NSNull.null, server ?: NSNull.null, client ?: NSNull.null]) {
      if (![task isKindOfClass:NSTask.class]) continue;
      if (task.running) [task terminate];
      WaitFixtureTask(task,1);
    }
    setenv("STINT_PROXY_TEST_TLS_PORT", [[NSString stringWithFormat:@"%u",echoPort] UTF8String],1);
    [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
  }
  Check(certificateReady, [@"TLS fixture certificate generated within deadline: " stringByAppendingString:diagnostic]);
  Check(serverReady, [@"TLS fixture starts only on loopback: " stringByAppendingString:diagnostic]);
  Check(clientCompleted && clientSucceeded, [@"TLS client completes authenticated CONNECT exchange: " stringByAppendingString:diagnostic]);
  Check(certificateVerified && negotiatedTLS, @"end-to-end TLS handshake verifies the fixture certificate");
  Check(responseCorrect, @"real TLS through CONNECT returns decrypted HTTP response byte exactly");
  Check(![NSFileManager.defaultManager fileExistsAtPath:folder], @"TLS credentials and fixture files removed");
}

int main(void) {
  @autoreleasepool {
    Fixture *http = [[Fixture alloc] initTunnel:NO], *tunnel = [[Fixture alloc] initTunnel:YES];
    setenv("STINT_PROXY_TEST_HTTP_PORT", [[NSString stringWithFormat:@"%u", http.port] UTF8String], 1);
    setenv("STINT_PROXY_TEST_TLS_PORT", [[NSString stringWithFormat:@"%u", tunnel.port] UTF8String], 1);
    StintLocalProxy *proxy = [[StintLocalProxy alloc] initWithPort:0]; NSError *error = nil;
    Check([proxy start:&error] && !error && proxy.running && proxy.port > 0, @"proxy starts on ephemeral loopback port");
    Check(proxy.token.length == 64 && [proxy.token rangeOfString:@"^[0-9a-fA-F]{64}$" options:NSRegularExpressionSearch].location != NSNotFound, @"health token has 64 random hex characters");
    StintLocalProxy *collision = [[StintLocalProxy alloc] initWithPort:proxy.port];
    Check(![collision start:&error] && error && !collision.running, @"occupied port fails explicitly");
    [collision stop];

    NSString *health = [NSString stringWithFormat:@"GET /_stint_health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Stint-Token: %@\r\n\r\n", proxy.token];
    NSData *healthResponse = Exchange(proxy.port, Bytes(health));
    Check(Status(healthResponse) == 200, @"authenticated local health succeeds");
    Check([[[NSString alloc] initWithData:healthResponse encoding:NSUTF8StringEncoding] containsString:proxy.token], @"health proves the running server token");
    for (NSString *bad in @[@"wrong", [proxy.token stringByAppendingString:@"a"], [proxy.token substringToIndex:63], @""]) {
      NSData *response = Exchange(proxy.port, Bytes([NSString stringWithFormat:@"GET /_stint_health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Stint-Token: %@\r\n\r\n", bad]));
      Check(Status(response) == 400 || Status(response) == 403, @"wrong health token denied");
      Check(![[[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding] containsString:proxy.token], @"invalid health never discloses token");
    }

    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 200, @"allowed HTTP forwards");
    NSString *forwarded = [[NSString alloc] initWithData:http.lastRequest encoding:NSISOLatin1StringEncoding];
    Check([forwarded hasPrefix:@"GET /resource?q=one HTTP/1.1\r\n"], @"HTTP target becomes origin form with query intact");
    Check([[forwarded lowercaseString] containsString:@"connection: close\r\n"], @"HTTP forwarding explicitly closes connection");
    NSString *hopRequest = @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nConnection: keep-alive, X-Hop\r\nProxy-Authorization: Basic should-stay-local\r\nProxy-Connection: keep-alive\r\nX-Stint-Token: local-token\r\nX-Hop: remove-me\r\nX-Origin: preserve-me\r\n\r\n";
    Check(Status(Exchange(proxy.port, Bytes(hopRequest))) == 200, @"HTTP accepts hop header cleanup");
    NSString *sanitized = [[[NSString alloc] initWithData:http.lastRequest encoding:NSISOLatin1StringEncoding] lowercaseString];
    Check(![sanitized containsString:@"proxy-authorization"] && ![sanitized containsString:@"proxy-connection"] && ![sanitized containsString:@"x-stint-token"] && ![sanitized containsString:@"x-hop:"], @"proxy credentials and hop headers stay local");
    Check([sanitized containsString:@"x-origin: preserve-me"], @"ordinary origin headers remain intact");
    NSMutableData *body = [NSMutableData dataWithLength:256*1024];
    uint8_t *bodyBytes = body.mutableBytes;
    for (NSUInteger i=0; i<body.length; i++) bodyBytes[i] = (uint8_t)(i*73+19);
    NSMutableData *post = [Bytes([NSString stringWithFormat:@"POST http://fixture.test/upload HTTP/1.1\r\nHost: fixture.test:80\r\nContent-Length: %lu\r\nConnection: keep-alive\r\n\r\n", (unsigned long)body.length]) mutableCopy];
    [post appendData:body];
    NSData *posted = Exchange(proxy.port, post);
    NSRange separator = [posted rangeOfData:Bytes(@"\r\n\r\n") options:0 range:NSMakeRange(0,posted.length)];
    Check(Status(posted) == 200 && separator.location != NSNotFound, @"HTTP body request receives upstream response");
    Check([[posted subdataWithRange:NSMakeRange(NSMaxRange(separator), posted.length-NSMaxRange(separator))] isEqualToData:body], @"HTTP binary request and response body remain byte exact");

    NSArray<NSString *> *malformed = @[
      @"CONNECT fixture.test:80 HTTP/1.1\r\nHost: fixture.test:80\r\n\r\n",
      @"CONNECT fixture.test:8443 HTTP/1.1\r\nHost: fixture.test:8443\r\n\r\n",
      @"CONNECT fixture.test:443x HTTP/1.1\r\nHost: fixture.test:443x\r\n\r\n",
      @"CONNECT fixture.test:443 HTTP/1.1\r\nHost: other.test:443\r\n\r\n",
      @"GET http://fixture.test:81/ HTTP/1.1\r\nHost: fixture.test:81\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: other.test\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nHost: fixture.test\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",
      @"POST http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n",
      @"POST http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n",
      @"GET /other HTTP/1.1\r\nHost: fixture.test\r\n\r\n",
      @"GET http://user:secret@fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\n\r\n",
      @"GET http://fixture.test/#fragment HTTP/1.1\r\nHost: fixture.test\r\n\r\n",
      @"GET http://bad..test/ HTTP/1.1\r\nHost: bad..test\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\n folded: value\r\n\r\n",
      @"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nContent-Length: -1\r\n\r\n",
      @"POST http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nContent-Length: 67108865\r\n\r\n",
      @"POST http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nContent-Length: 1,1\r\n\r\n"
    ];
    for (NSString *request in malformed) {
      NSUInteger before = http.requestCount;
      NSInteger status = Status(Exchange(proxy.port, Bytes(request)));
      Check(status >= 400 && status < 500, [@"malformed request rejected: " stringByAppendingString:[request componentsSeparatedByString:@"\r\n"].firstObject]);
      Check(http.requestCount == before, @"malformed request never reaches HTTP upstream");
    }
    for (NSString *control in @[@"\r", @"\n"]) {
      NSUInteger before = http.acceptCount;
      NSString *request = [NSString stringWithFormat:@"GET http://fixture.test/path%@injected HTTP/1.1\r\nHost: fixture.test\r\n\r\n", control];
      Check(Status(Exchange(proxy.port, Bytes(request))) == 400, @"bare CR or LF inside request target is rejected");
      usleep(10000);
      Check(http.acceptCount == before, @"bare request-target control never opens an upstream connection");
    }
    NSUInteger beforePipeline = http.requestCount;
    NSData *pipelined = Exchange(proxy.port, Bytes([HTTP(@"fixture.test") stringByAppendingString:HTTP(@"fixture.test")]));
    Check(Status(pipelined) >= 400 && Status(pipelined) < 500, @"pipelined HTTP requests rejected");
    Check(http.requestCount == beforePipeline, @"pipelined bytes do not reach HTTP upstream");
    NSMutableString *oversized = [NSMutableString stringWithString:@"GET http://fixture.test/ HTTP/1.1\r\nHost: fixture.test\r\nX-Large: "];
    [oversized appendString:[@"x" stringByPaddingToLength:33000 withString:@"x" startingAtIndex:0]];
    [oversized appendString:@"\r\n\r\n"];
    NSInteger oversizedStatus = Status(Exchange(proxy.port, Bytes(oversized)));
    Check(oversizedStatus >= 400 && oversizedStatus < 500, @"oversized headers rejected");

    [proxy updatePolicy:Policy(proxy, @[@"fixture.test", @"cannot-resolve.invalid"], 20000)];
    for (NSString *host in @[@"fixture.test", @"deep.sub.fixture.test", @"FIXTURE.TEST", @"fixture.test.", @"cannot-resolve.invalid"]) {
      Check(Status(Exchange(proxy.port, Bytes(HTTP(host)))) == 403, @"active policy blocks HTTP and subdomains before DNS");
      Check(Status(Exchange(proxy.port, Bytes(CONNECT(host)))) == 403, @"active policy blocks CONNECT and subdomains before DNS");
    }
    [proxy updatePolicy:Policy(proxy, @[@"blocked.fixture.test"], 20000)];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"notblocked.fixture.test")))) == 200, @"domain matching respects a complete label boundary");
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"child.blocked.fixture.test")))) == 403, @"nested blocked subdomain denied");
    [proxy updatePolicy:@{@"active":@NO}];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"blocked.fixture.test")))) == 200, @"inactive focus releases blocking");
    NSMutableDictionary *numericActive = [Policy(proxy, @[@"fixture.test"], 20000) mutableCopy];
    [proxy updatePolicy:numericActive];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 403, @"valid boolean active starts blocking");
    numericActive[@"active"] = @1;
    [proxy updatePolicy:numericActive];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 200, @"numeric active is malformed and releases blocking");
    [proxy updatePolicy:Policy(proxy, @[@"fixture.test"], -1)];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 200, @"already expired policy never blocks");
    NSDictionary *expiring = Policy(proxy, @[@"fixture.test"], 150);
    [proxy updatePolicy:expiring];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 403, @"short live lease blocks initially");
    usleep(250000);
    [proxy updatePolicy:expiring];
    Check(Status(Exchange(proxy.port, Bytes(HTTP(@"fixture.test")))) == 200, @"lease expires and identical input cannot extend it");

    [proxy updatePolicy:@{@"active":@NO}];
    int binaryTunnel = OpenTunnel(proxy, @"fixture.test");
    int smallBuffer = 1024; setsockopt(binaryTunnel, SOL_SOCKET, SO_SNDBUF, &smallBuffer, sizeof(smallBuffer));
    dispatch_group_t transfer = dispatch_group_create(); __block BOOL sent = NO;
    dispatch_group_async(transfer, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
      sent = WriteAll(binaryTunnel, body); shutdown(binaryTunnel, SHUT_WR);
    });
    usleep(100000);
    NSData *echoed = ReadToClose(binaryTunnel);
    Check(dispatch_group_wait(transfer, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)) == 0 && sent, @"tunnel writer handles partial writes under backpressure");
    NSMutableData *expected = [body mutableCopy]; [expected appendData:TunnelTail()];
    Check([echoed isEqualToData:expected], @"opaque tunnel preserves binary bytes and upstream response after client half close");
    Check(ClosesSoon(binaryTunnel), @"tunnel closes after both directions finish");
    close(binaryTunnel);

    int reverseTunnel = OpenTunnel(proxy, @"fixture.test");
    Check(WriteAll(reverseTunnel, Bytes(@"~")), @"ask fixture to half close its write direction");
    Check([ReadCount(reverseTunnel,17) isEqualToData:Bytes(@"upstream-finished")], @"upstream sends its final bytes");
    Check(ClosesSoon(reverseTunnel), @"upstream half close reaches client promptly");
    Check(WriteAll(reverseTunnel, body), @"client can keep sending after upstream half close");
    shutdown(reverseTunnel, SHUT_WR);
    for (NSUInteger retry=0; retry<100 && !tunnel.requestCount; retry++) usleep(10000);
    Check([tunnel.lastRequest isEqualToData:body], @"upstream receives complete body after its own half close");
    close(reverseTunnel);

    int earlyTunnel = Dial(proxy.port); Check(earlyTunnel >= 0, @"connect tunnel with early opaque bytes");
    NSMutableData *early = [Bytes(CONNECT(@"fixture.test")) mutableCopy];
    NSData *earlyPayload = [body subdataWithRange:NSMakeRange(0,1024)]; [early appendData:earlyPayload];
    Check(WriteAll(earlyTunnel, early) && Status(ReadHeaders(earlyTunnel)) == 200, @"CONNECT accepts bytes coalesced with handshake");
    Check([ReadCount(earlyTunnel,earlyPayload.length) isEqualToData:earlyPayload], @"early tunnel bytes are forwarded exactly once");
    close(earlyTunnel);

    int blockedTunnel = OpenTunnel(proxy, @"blocked.fixture.test");
    int allowedTunnel = OpenTunnel(proxy, @"allowed.fixture.test");
    Check(WriteAll(blockedTunnel, Bytes(@"before")) && [ReadCount(blockedTunnel,6) isEqualToData:Bytes(@"before")], @"existing tunnel transports before policy change");
    [proxy updatePolicy:Policy(proxy, @[@"blocked.fixture.test"], 20000)];
    Check(ClosesSoon(blockedTunnel), @"policy update closes existing blocked tunnel promptly");
    Check(WriteAll(allowedTunnel, Bytes(@"after")) && [ReadCount(allowedTunnel,5) isEqualToData:Bytes(@"after")], @"policy update preserves existing allowed tunnel");
    close(blockedTunnel); close(allowedTunnel);
    [proxy updatePolicy:@{@"active":@NO}];
    usleep(100000);

    TestTLS(proxy, tunnel.port);

    setenv("STINT_PROXY_TEST_DNS_DELAY_MS", "100", 1);
    dispatch_group_t burst = dispatch_group_create();
    NSMutableArray<NSNumber *> *burstResults = [NSMutableArray array];
    for (NSUInteger i=0; i<12; i++) [burstResults addObject:@0];
    for (NSUInteger i=0; i<12; i++) {
      dispatch_group_async(burst, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
          int fd = Dial(proxy.port); NSInteger status = 0;
          if (fd >= 0) {
            NSString *host = [NSString stringWithFormat:@"origin%lu.fixture.test", (unsigned long)i];
            if (WriteAll(fd, Bytes(CONNECT(host)))) status = Status(ReadHeaders(fd));
            close(fd);
          }
          @synchronized(burstResults) { burstResults[i] = @(status); }
        }
      });
    }
    Check(dispatch_group_wait(burst, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC)) == 0, @"burst DNS work completes within its deadline");
    unsetenv("STINT_PROXY_TEST_DNS_DELAY_MS");
    for (NSNumber *status in burstResults) Check(status.integerValue == 200, @"12 concurrent origins queue behind DNS workers without 503");
    usleep(100000);

    // Hold incomplete requests, so concurrency is bounded even before headers
    // are parsed or DNS work is queued. Extra clients may receive 503 or EOF.
    NSMutableArray<NSNumber *> *held = [NSMutableArray array];
    for (NSUInteger i=0; i<128; i++) {
      int fd = Dial(proxy.port); Check(fd >= 0, @"open held header connection");
      Check(WriteAll(fd, Bytes(@"GET ")), @"hold incomplete request"); [held addObject:@(fd)];
    }
    int excess = Dial(proxy.port); Check(excess >= 0, @"connect excess client");
    WriteAll(excess, Bytes(HTTP(@"fixture.test")));
    struct pollfd readiness = {.fd=excess, .events=POLLIN|POLLHUP};
    Check(poll(&readiness,1,2000) > 0, @"concurrency cap rejects excess promptly");
    NSData *excessResponse = ReadToClose(excess);
    Check(!excessResponse.length || Status(excessResponse) >= 400, @"concurrency cap does not start a 129th session"); close(excess);
    Check(Status(Exchange(proxy.port, Bytes(health))) == 200, @"authenticated health remains available at the 128 normal session cap");
    double stopStart = NSProcessInfo.processInfo.systemUptime;
    [proxy stop];
    Check(NSProcessInfo.processInfo.systemUptime-stopStart < 2, @"stop remains bounded with pending requests");
    Check(!proxy.running, @"stop clears running status");
    for (NSNumber *client in held) { Check(ClosesSoon(client.intValue), @"stop closes every pending client"); close(client.intValue); }
    Check(Dial(proxy.port) < 0, @"stopped proxy no longer accepts connections");
    [proxy stop];
    for (NSUInteger cycle=0; cycle<20; cycle++) {
      error = nil;
      Check([proxy start:&error] && !error && proxy.running, @"repeated start creates a running generation");
      int pending = Dial(proxy.port); Check(pending >= 0, @"restarted generation accepts clients");
      Check(WriteAll(pending, Bytes(@"GET ")), @"restarted generation holds a pending client");
      [proxy stop];
      Check(!proxy.running && ClosesSoon(pending), @"repeated stop clears state and closes generation clients");
      close(pending);
    }
    [http stop]; [tunnel stop];
    printf("Local proxy: %lu checks passed\n", (unsigned long)checks);
  }
  return 0;
}
