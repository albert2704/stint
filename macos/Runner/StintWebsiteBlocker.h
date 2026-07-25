#import <Foundation/Foundation.h>
@interface StintWebsiteBlocker : NSObject
@property(nonatomic, copy) void (^statusChanged)(NSDictionary *status);
- (void)update:(NSDictionary *)state;
- (void)statusWithReply:(void (^)(NSDictionary *status))reply;
- (void)enableWithReply:(void (^)(NSDictionary *status))reply;
- (void)removeWithReply:(void (^)(NSDictionary *status))reply;
@end
