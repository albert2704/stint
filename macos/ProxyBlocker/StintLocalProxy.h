#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// An unprivileged IPv4-loopback HTTP/CONNECT proxy. Call stop before app exit.
@interface StintLocalProxy : NSObject
@property(nonatomic, readonly) uint16_t port;
@property(nonatomic, readonly, copy) NSString *token;
@property(nonatomic, readonly) BOOL running;
- (instancetype)initWithPort:(uint16_t)port NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)start:(NSError * _Nullable * _Nullable)error;
- (void)stop;
- (void)updatePolicy:(NSDictionary *)policy;
@end

NS_ASSUME_NONNULL_END
