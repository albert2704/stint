#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Shared validation has no OS side effects and is used by app and helper.
FOUNDATION_EXPORT NSArray<NSString *> * _Nullable StintValidatedDomains(id _Nullable value);

@interface StintBlockerPolicy : NSObject
@property(nonatomic, readonly, copy) NSArray<NSString *> *domains;
@property(nonatomic, readonly, copy) NSString *session;
@property(nonatomic, readonly) uid_t ownerUID;
@property(nonatomic, readonly) double wallExpiry;
@property(nonatomic, readonly) double uptimeExpiry;
+ (instancetype)policyWithDictionary:(id _Nullable)value now:(double)now uptime:(double)uptime;
- (BOOL)isEffectiveAt:(double)now uptime:(double)uptime;
@end
NS_ASSUME_NONNULL_END
