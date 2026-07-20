#import "StintBlockerPolicy.h"
#import <math.h>


NSArray<NSString *> *StintValidatedDomains(id value) {
  if (![value isKindOfClass:NSArray.class] || [value count] > 200) return nil;
  NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
  for (id domain in value) {
    if (![domain isKindOfClass:NSString.class] || [domain length] > 253 || ![domain containsString:@"."] || [domain hasSuffix:@".localhost"]) return nil;
    NSArray *labels = [domain componentsSeparatedByString:@"."];
    for (NSString *label in labels) {
      if ([label rangeOfString:@"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    }
    if ([[labels lastObject] rangeOfString:@"[a-z]" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    [result addObject:domain];
  }
  return result.array;
}

static BOOL StintNumber(id value) {
  return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() && isfinite([value doubleValue]);
}

@implementation StintBlockerPolicy
+ (instancetype)policyWithDictionary:(id)value now:(double)now uptime:(double)uptime {
  StintBlockerPolicy *policy = [[self alloc] init];
  policy->_domains = @[];
  policy->_session = @"";
  if (![value isKindOfClass:NSDictionary.class] || !isfinite(now) || !isfinite(uptime)) return policy;
  NSDictionary *data = value;
  if (!StintNumber(data[@"version"]) || ![@[@1, @2] containsObject:data[@"version"]] ||
      ![data[@"active"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)data[@"active"]) != CFBooleanGetTypeID() || ![data[@"active"] boolValue]) return policy;
  NSString *session = data[@"sessionId"];
  NSArray *domains = StintValidatedDomains(data[@"domains"]);
  if (![session isKindOfClass:NSString.class] || !session.length || session.length > 200 || !domains.count) return policy;
  for (NSString *key in @[@"ownerUID", @"issuedAtMilliseconds", @"deadlineMilliseconds", @"leaseExpiresAt"])
    if (!StintNumber(data[key])) return policy;
  double uid = [data[@"ownerUID"] doubleValue], issued = [data[@"issuedAtMilliseconds"] doubleValue];
  double expiry = MIN([data[@"deadlineMilliseconds"] doubleValue], [data[@"leaseExpiresAt"] doubleValue]);
  if (uid < 1 || uid > UINT32_MAX || floor(uid) != uid || issued > now + 1000 ||
      expiry <= now || expiry <= issued || expiry - issued > 30000 || now < 0 || uptime < 0) return policy;
  policy->_domains = domains;
  policy->_session = session;
  policy->_ownerUID = (uid_t)uid;
  policy->_wallExpiry = expiry;
  policy->_uptimeExpiry = uptime + MIN(30, (expiry - now) / 1000);
  return policy;
}
- (BOOL)isEffectiveAt:(double)now uptime:(double)uptime {
  return self.domains.count > 0 && self.session.length && now < self.wallExpiry && uptime < self.uptimeExpiry;
}
@end
