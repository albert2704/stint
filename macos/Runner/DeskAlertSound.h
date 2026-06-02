#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns a notification sound filename containing the chosen macOS chime
/// twice, separated by 250 ms. Generates and caches it in this app's Library/
/// Sounds at runtime. Only Glass, Ping, Pop, Funk, Submarine, and Basso are valid.
/// Returns nil when decoding or writing fails; callers may use the system default.
FOUNDATION_EXPORT NSString *_Nullable DeskRepeatedAlertSoundName(NSString *soundName);

NS_ASSUME_NONNULL_END
