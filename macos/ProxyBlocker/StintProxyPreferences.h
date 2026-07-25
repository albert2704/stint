#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

/// Serial-use routing owner. A failed operation never establishes protection.
@interface StintProxyPreferences : NSObject
@property(nonatomic, readonly, getter=isActive) BOOL active;
- (instancetype)initWithJournalPath:(NSString *)path expectedOwner:(uid_t)owner;
- (BOOL)activateForDomains:(NSArray<NSString *> *)domains error:(NSError **)error;
- (BOOL)restore:(NSError **)error;
- (BOOL)validateActive:(NSError **)error;
@end

#if defined(STINT_PROXY_TESTING) || defined(STINT_PROXY_INTERNAL)
/// Test seams: no test needs permission to read or change system preferences.
@protocol StintProxyPreferencesBackend <NSObject>
- (BOOL)lock:(NSError **)error;
- (void)unlock;
- (void)synchronize;
/// Stable service ID -> { enabled: NSNumber, protocolEnabled: NSNumber, proxies: NSDictionary }.
- (nullable NSDictionary<NSString *, NSDictionary *> *)services:(NSError **)error;
- (BOOL)setProxies:(NSDictionary *)proxies forService:(NSString *)service error:(NSError **)error;
- (BOOL)commit:(NSError **)error;
- (BOOL)apply:(NSError **)error;
@end

@protocol StintProxyJournal <NSObject>
/// nil and no error means there is no recovery journal.
- (nullable NSDictionary *)read:(NSError **)error;
- (BOOL)write:(NSDictionary *)journal error:(NSError **)error;
- (BOOL)remove:(NSError **)error;
@end

@interface StintProxyPreferences (Testing)
- (instancetype)initWithBackend:(id<StintProxyPreferencesBackend>)backend journal:(id<StintProxyJournal>)journal;
@end

/// Exercises the production filesystem adapter against isolated test fixtures.
#ifdef STINT_PROXY_TESTING
id<StintProxyJournal> StintProxyTestJournal(NSString *path, uid_t expectedOwner);
#endif
#endif

NS_ASSUME_NONNULL_END
