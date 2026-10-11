#import <Foundation/Foundation.h>
// Pure transformation, then bounded filesystem adapter. Production passes uid 0.
NSData *StintHostsData(NSData *original, NSArray<NSString *> *domains, NSError **error);
BOOL StintWriteHosts(NSString *path, NSArray<NSString *> *domains, uid_t owner, BOOL *changed, NSError **error);
int StintOpenPolicyDirectory(NSString *path, uid_t owner);
NSData *StintReadBoundedAt(int directory, const char *name, uid_t owner, NSUInteger limit);
BOOL StintWriteStatusAt(int directory, NSDictionary *status);
