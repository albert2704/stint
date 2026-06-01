#import "DeskAlertSound.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import <stdio.h>
#import <string.h>

static NSString *const DeskAlertCacheVersion = @"v1";
static NSTimeInterval const DeskAlertGapSeconds = 0.25;
static NSTimeInterval const DeskAlertMaximumSeconds = 29.5;

static BOOL DeskAllowedAlertSound(NSString *name) {
  return [name isKindOfClass:NSString.class] &&
      [@[@"Glass", @"Ping", @"Pop", @"Funk", @"Submarine", @"Basso"] containsObject:name];
}

static BOOL DeskValidRepeatedSound(NSURL *url, AVAudioFramePosition frames,
                                   AVAudioFormat *format) {
  NSDictionary *attributes = [url resourceValuesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
                                                 error:NULL];
  if (![attributes[NSURLIsRegularFileKey] boolValue] ||
      [attributes[NSURLFileSizeKey] unsignedLongLongValue] == 0) return NO;
  AVAudioFile *cached = [[AVAudioFile alloc] initForReading:url error:NULL];
  if (!cached || cached.length != frames ||
      cached.processingFormat.channelCount != format.channelCount ||
      fabs(cached.processingFormat.sampleRate - format.sampleRate) > 0.1) return NO;
  const AudioStreamBasicDescription *description = cached.fileFormat.streamDescription;
  return description->mFormatID == kAudioFormatLinearPCM && description->mBitsPerChannel == 16 &&
      (double)cached.length / cached.processingFormat.sampleRate < 30.0;
}

// The explicit directory keeps generation testable without touching preferences
// or the real app container. Production callers always use the public function.
static NSString *DeskRepeatedAlertSoundInDirectory(NSString *name, NSURL *directory) {
  if (!DeskAllowedAlertSound(name) || !directory.isFileURL) return nil;
  NSURL *sourceURL = [NSURL fileURLWithPath:
      [NSString stringWithFormat:@"/System/Library/Sounds/%@.aiff", name]];
  AVAudioFile *source = [[AVAudioFile alloc] initForReading:sourceURL
      commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:NULL];
  AVAudioFormat *format = source.processingFormat;
  double sampleRate = format.sampleRate;
  AVAudioFramePosition sourceFrames = source.length;
  if (!source || !isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 192000 ||
      format.channelCount < 1 || format.channelCount > 2 || sourceFrames <= 0 ||
      (double)sourceFrames / sampleRate > (DeskAlertMaximumSeconds - DeskAlertGapSeconds) / 2) return nil;
  AVAudioFrameCount gapFrames = (AVAudioFrameCount)llround(sampleRate * DeskAlertGapSeconds);
  AVAudioFramePosition totalFrames = sourceFrames * 2 + gapFrames;
  if (totalFrames > UINT32_MAX || (double)totalFrames / sampleRate >= 30.0) return nil;

  NSString *filename = [NSString stringWithFormat:@"FocusDesk-%@-%@-twice.wav", DeskAlertCacheVersion, name];
  NSURL *destination = [directory URLByAppendingPathComponent:filename];
  if (DeskValidRepeatedSound(destination, totalFrames, format)) return filename;
  if (![NSFileManager.defaultManager createDirectoryAtURL:directory
      withIntermediateDirectories:YES attributes:nil error:NULL]) return nil;

  AVAudioPCMBuffer *chime = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
      frameCapacity:(AVAudioFrameCount)sourceFrames];
  if (!chime || ![source readIntoBuffer:chime frameCount:(AVAudioFrameCount)sourceFrames error:NULL] ||
      chime.frameLength != sourceFrames || !chime.floatChannelData) return nil;
  AVAudioPCMBuffer *repeated = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
      frameCapacity:(AVAudioFrameCount)totalFrames];
  if (!repeated || !repeated.floatChannelData) return nil;
  repeated.frameLength = (AVAudioFrameCount)totalFrames;
  for (AVAudioChannelCount channel = 0; channel < format.channelCount; channel++) {
    float *output = repeated.floatChannelData[channel];
    memset(output, 0, (size_t)totalFrames * sizeof(float));
    memcpy(output, chime.floatChannelData[channel], (size_t)sourceFrames * sizeof(float));
    memcpy(output + sourceFrames + gapFrames, chime.floatChannelData[channel],
           (size_t)sourceFrames * sizeof(float));
  }

  NSURL *temporary = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@".FocusDesk-%@.wav", NSUUID.UUID.UUIDString]];
  NSDictionary *settings = @{
    AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(sampleRate),
    AVNumberOfChannelsKey: @(format.channelCount), AVLinearPCMBitDepthKey: @16,
    AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsBigEndianKey: @NO,
    AVLinearPCMIsNonInterleaved: @NO,
  };
  BOOL written = NO;
  @autoreleasepool {
    AVAudioFile *writer = [[AVAudioFile alloc] initForWriting:temporary settings:settings
        commonFormat:AVAudioPCMFormatFloat32 interleaved:NO error:NULL];
    written = writer && [writer writeFromBuffer:repeated error:NULL];
    // Releasing the writer finalizes the WAV header on supported macOS versions.
    // AVAudioFile.close is macOS 15+, while this app also supports macOS 12.
    writer = nil;
  }
  if (!written || !DeskValidRepeatedSound(temporary, totalFrames, format) ||
      rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
    [NSFileManager.defaultManager removeItemAtURL:temporary error:NULL];
    return nil;
  }
  return filename;
}

NSString *DeskRepeatedAlertSoundName(NSString *soundName) {
  if (!DeskAllowedAlertSound(soundName)) return nil;
  static NSObject *cacheLock;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{ cacheLock = [[NSObject alloc] init]; });
  @synchronized (cacheLock) {
    NSURL *library = [NSFileManager.defaultManager URLForDirectory:NSLibraryDirectory
        inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
    if (!library) return nil;
    return DeskRepeatedAlertSoundInDirectory(soundName,
        [library URLByAppendingPathComponent:@"Sounds" isDirectory:YES]);
  }
}
