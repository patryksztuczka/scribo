#import "capture.h"
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <atomic>
#include <cstdlib>
#include <cstring>
#import <dispatch/dispatch.h>

// Simple singleton state for one capture session
static std::atomic<bool> g_isCapturing(false);
static SCStream *g_stream = nil;
static ExtAudioFileRef g_audioFile = NULL;
static std::atomic<bool> g_clientFormatSet(false);
static std::atomic<bool> g_micClientFormatSet(false);
static AVAudioEngine *g_micEngine = nil;
static ExtAudioFileRef g_micFile = NULL;

static char *dup_cstr(const char *s) {
  if (!s) {
    char *r = (char *)std::malloc(1);
    r[0] = 0;
    return r;
  }
  size_t len = std::strlen(s);
  char *r = (char *)std::malloc(len + 1);
  std::memcpy(r, s, len + 1);
  return r;
}

void sc_free(char *s) {
  if (s)
    std::free(s);
}

@interface SCAudioWriter : NSObject <SCStreamOutput>
@end

@implementation SCAudioWriter

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type {
  if (type != SCStreamOutputTypeAudio)
    return;
  if (!g_audioFile)
    return;

  CFRetain(sampleBuffer);

  if (!g_clientFormatSet.load()) {
    CMAudioFormatDescriptionRef fmt =
        (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(
            sampleBuffer);
    if (fmt) {
      const AudioStreamBasicDescription *inAsbd =
          CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
      if (inAsbd) {
        OSStatus ps = ExtAudioFileSetProperty(
            g_audioFile, kExtAudioFileProperty_ClientDataFormat,
            sizeof(AudioStreamBasicDescription), inAsbd);
        if (ps != noErr) {
          NSLog(@"ExtAudioFileSetProperty(ClientDataFormat) failed: %d",
                (int)ps);
        } else {
          g_clientFormatSet.store(true);
        }
      }
    }
  }

  CMBlockBufferRef blockBuffer = NULL;
  size_t sizeNeeded = 0;
  // First call to get required size with alignment flag
  OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, &sizeNeeded, NULL, 0, kCFAllocatorDefault,
      kCFAllocatorDefault,
      kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
  if (status != noErr || sizeNeeded == 0) {
    NSLog(@"GetAudioBufferList (size query) failed: %d", (int)status);
    if (blockBuffer)
      CFRelease(blockBuffer);
    CFRelease(sampleBuffer);
    return;
  }
  AudioBufferList *bufferList = (AudioBufferList *)std::malloc(sizeNeeded);
  if (!bufferList) {
    if (blockBuffer)
      CFRelease(blockBuffer);
    CFRelease(sampleBuffer);
    return;
  }
  // Second call to fill the buffer list we allocated
  status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, NULL, bufferList, sizeNeeded, kCFAllocatorDefault,
      kCFAllocatorDefault,
      kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
  if (status != noErr) {
    NSLog(@"GetAudioBufferList failed: %d", (int)status);
    if (blockBuffer)
      CFRelease(blockBuffer);
    std::free(bufferList);
    CFRelease(sampleBuffer);
    return;
  }

  UInt32 frames = (UInt32)CMSampleBufferGetNumSamples(sampleBuffer);
  OSStatus ws = ExtAudioFileWrite(g_audioFile, frames, bufferList);
  if (ws != noErr) {
    NSLog(@"ExtAudioFileWrite failed: %d (frames=%u)", (int)ws,
          (unsigned)frames);
  }

  if (blockBuffer)
    CFRelease(blockBuffer);
  std::free(bufferList);
  CFRelease(sampleBuffer);
}

@end

static SCAudioWriter *g_writer = nil;

static BOOL ensureAudioFileAtPath(NSString *path, NSError **error) {
  // Target WAV: 16-bit PCM, 44.1kHz, stereo
  double sampleRate = 44100.0;
  UInt32 channels = 2;
  // Create AudioStreamBasicDescription for LPCM output
  AudioStreamBasicDescription asbd = {0};
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags =
      kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mFramesPerPacket = 1;
  asbd.mChannelsPerFrame = channels;
  asbd.mBitsPerChannel = 16;
  asbd.mBytesPerFrame = (asbd.mBitsPerChannel / 8) * asbd.mChannelsPerFrame;
  asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;

  // Ensure parent directory exists
  NSString *parent = [path stringByDeletingLastPathComponent];
  if (parent.length > 0) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    BOOL exists = [fm fileExistsAtPath:parent isDirectory:&isDir];
    if (!exists || !isDir) {
      NSError *mkErr = nil;
      BOOL ok = [fm createDirectoryAtPath:parent
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&mkErr];
      if (!ok) {
        if (error)
          *error = mkErr;
        return NO;
      }
    }
  }

  CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
  OSStatus st =
      ExtAudioFileCreateWithURL(url, kAudioFileWAVEType, &asbd, NULL,
                                kAudioFileFlags_EraseFile, &g_audioFile);
  if (st != noErr) {
    if (error)
      *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:st
                               userInfo:nil];
    return NO;
  }
  return YES;
}

static BOOL ensureAudioFileAtPathWithChannels(NSString *path, double sampleRate,
                                              UInt32 channels,
                                              NSError **error) {
  AudioStreamBasicDescription asbd = {0};
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags =
      kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mFramesPerPacket = 1;
  asbd.mChannelsPerFrame = channels;
  asbd.mBitsPerChannel = 16;
  asbd.mBytesPerFrame = (asbd.mBitsPerChannel / 8) * asbd.mChannelsPerFrame;
  asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;

  // Ensure parent directory exists
  NSString *parent = [path stringByDeletingLastPathComponent];
  if (parent.length > 0) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    BOOL exists = [fm fileExistsAtPath:parent isDirectory:&isDir];
    if (!exists || !isDir) {
      NSError *mkErr = nil;
      BOOL ok = [fm createDirectoryAtPath:parent
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&mkErr];
      if (!ok) {
        if (error)
          *error = mkErr;
        return NO;
      }
    }
  }

  CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
  OSStatus st =
      ExtAudioFileCreateWithURL(url, kAudioFileWAVEType, &asbd, NULL,
                                kAudioFileFlags_EraseFile, &g_micFile);
  if (st != noErr) {
    if (error)
      *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:st
                               userInfo:nil];
    return NO;
  }
  return YES;
}

static SCRunningApplication *findApp(NSArray<SCRunningApplication *> *apps,
                                     NSString *idStr)
    API_AVAILABLE(macos(12.3)) {
  // Accept PID or bundle ID
  // If idStr is all digits -> PID
  BOOL isDigits = YES;
  for (NSUInteger i = 0; i < idStr.length; i++) {
    unichar c = [idStr characterAtIndex:i];
    if (c < '0' || c > '9') {
      isDigits = NO;
      break;
    }
  }
  if (isDigits) {
    pid_t pid = (pid_t)[idStr integerValue];
    for (SCRunningApplication *a in apps) {
      if (a.processID == pid)
        return a;
    }
  } else {
    for (SCRunningApplication *a in apps) {
      if ([a.bundleIdentifier isEqualToString:idStr])
        return a;
    }
  }
  return nil;
}

static SCWindow *findWindow(NSArray<SCWindow *> *windows, NSString *idStr)
    API_AVAILABLE(macos(12.3)) {
  uint64_t wid = (uint64_t)[idStr longLongValue];
  for (SCWindow *w in windows) {
    if (w.windowID == wid)
      return w;
  }
  return nil;
}

static SCDisplay *findDisplay(NSArray<SCDisplay *> *displays, NSString *idStr)
    API_AVAILABLE(macos(12.3)) {
  uint32_t did = (uint32_t)[idStr intValue];
  for (SCDisplay *d in displays) {
    if (d.displayID == did)
      return d;
  }
  return nil;
}

bool sc_start_capture(const char *kind, const char *id, const char *out_path,
                      char **out_err) {
  @autoreleasepool {
    if (!kind || !id || !out_path) {
      if (out_err)
        *out_err = dup_cstr("invalid arguments");
      return false;
    }
    if (!@available(macOS 12.3, *)) {
      if (out_err)
        *out_err = dup_cstr("Requires macOS 12.3+");
      return false;
    }
    if (g_isCapturing.load()) {
      if (out_err)
        *out_err = dup_cstr("capture already running");
      return false;
    }

    NSString *kindStr = [NSString stringWithUTF8String:kind];
    NSString *idStr = [NSString stringWithUTF8String:id];
    NSString *path = [NSString stringWithUTF8String:out_path];

    __block SCShareableContent *content = nil;
    __block NSError *err = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [SCShareableContent
        getShareableContentWithCompletionHandler:^(
            SCShareableContent *_Nullable c, NSError *_Nullable e) {
          content = c;
          err = e;
          dispatch_semaphore_signal(sema);
        }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    if (err || !content) {
      if (out_err)
        *out_err = dup_cstr(
            [[NSString stringWithFormat:@"shareableContent error: %@",
                                        err.localizedDescription ?: @"unknown"]
                UTF8String]);
      return false;
    }

    SCContentFilter *filter = nil;
    if ([kindStr isEqualToString:@"application"]) {
      SCRunningApplication *app = findApp(content.applications, idStr);
      if (!app) {
        if (out_err)
          *out_err = dup_cstr("application not found");
        return false;
      }
      SCDisplay *disp = content.displays.firstObject;
      if (!disp) {
        if (out_err)
          *out_err = dup_cstr("no displays available");
        return false;
      }
      filter = [[SCContentFilter alloc] initWithDisplay:disp
                                  includingApplications:@[ app ]
                                       exceptingWindows:@[]];
    } else if ([kindStr isEqualToString:@"window"]) {
      SCWindow *win = findWindow(content.windows, idStr);
      if (!win) {
        if (out_err)
          *out_err = dup_cstr("window not found");
        return false;
      }
      filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:win];
    } else if ([kindStr isEqualToString:@"display"]) {
      SCDisplay *disp = findDisplay(content.displays, idStr);
      if (!disp) {
        if (out_err)
          *out_err = dup_cstr("display not found");
        return false;
      }
      filter = [[SCContentFilter alloc] initWithDisplay:disp
                                       excludingWindows:@[]];
    } else {
      if (out_err)
        *out_err = dup_cstr("unknown kind");
      return false;
    }

    NSError *fileErr = nil;
    if (!ensureAudioFileAtPath(path, &fileErr)) {
      if (out_err)
        *out_err = dup_cstr([[NSString
            stringWithFormat:@"audio file error: %@",
                             fileErr.localizedDescription ?: @"unknown"]
            UTF8String]);
      return false;
    }

    SCStreamConfiguration *cfg = [SCStreamConfiguration new];
    cfg.capturesAudio = YES;
    cfg.sampleRate = 48000;
    cfg.channelCount = 2;

    g_writer = [SCAudioWriter new];

    g_stream = [[SCStream alloc] initWithFilter:filter
                                  configuration:cfg
                                       delegate:nil];
    if (!g_stream) {
      if (out_err)
        *out_err = dup_cstr("failed to create SCStream");
      if (g_audioFile) {
        ExtAudioFileDispose(g_audioFile);
        g_audioFile = NULL;
      }
      return false;
    }

    // Add output for audio
    NSError *addErr = nil;
    [g_stream addStreamOutput:g_writer
                         type:SCStreamOutputTypeAudio
           sampleHandlerQueue:dispatch_get_global_queue(
                                  QOS_CLASS_USER_INITIATED, 0)
                        error:&addErr];
    if (addErr) {
      if (out_err)
        *out_err = dup_cstr([[NSString
            stringWithFormat:@"add output error: %@",
                             addErr.localizedDescription ?: @"unknown"]
            UTF8String]);
      [g_stream stopCaptureWithCompletionHandler:^(NSError *_Nullable error){
      }];
      g_stream = nil;
      if (g_audioFile) {
        ExtAudioFileDispose(g_audioFile);
        g_audioFile = NULL;
      }
      return false;
    }

    // Set client data format for ExtAudioFile to match incoming stream format
    // if available We stick to 16-bit PCM target; ExtAudioFile will convert if
    // configured. For simplicity, we skip custom client format and assume PCM
    // Int16 input (works on 13+).

    [g_stream startCaptureWithCompletionHandler:^(NSError *_Nullable startErr) {
      if (startErr) {
        if (g_audioFile) {
          ExtAudioFileDispose(g_audioFile);
          g_audioFile = NULL;
        }
        NSLog(@"startCapture error: %@", startErr.localizedDescription);
      } else {
        NSLog(@"SCStream started (audio=%@)",
              cfg.capturesAudio ? @"YES" : @"NO");
      }
    }];

    // Start microphone capture to separate file: same base + "-mic.wav"
    @try {
      // Request permission if needed
      AVAuthorizationStatus auth =
          [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
      if (auth == AVAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                 completionHandler:^(BOOL granted) {
                                   dispatch_semaphore_signal(s);
                                 }];
        dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
        auth =
            [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
      }
      if (auth != AVAuthorizationStatusAuthorized) {
        NSLog(@"Mic access not authorized; skipping mic capture");
      } else {
        g_micEngine = [AVAudioEngine new];
        AVAudioInputNode *input = g_micEngine.inputNode;
        AVAudioFormat *inFormat = [input inputFormatForBus:0];
        NSString *baseNoExt = [path stringByDeletingPathExtension];
        NSString *micPath = [baseNoExt stringByAppendingString:@"-mic.wav"];
        NSError *micErr = nil;
        UInt32 micChannels = (UInt32)inFormat.channelCount;
        if (!ensureAudioFileAtPathWithChannels(micPath, 48000.0, micChannels,
                                               &micErr)) {
          NSLog(@"mic file error: %@", micErr.localizedDescription);
        } else {
          const AudioStreamBasicDescription *inAsbd =
              inFormat.streamDescription;
          OSStatus ps = ExtAudioFileSetProperty(
              g_micFile, kExtAudioFileProperty_ClientDataFormat,
              sizeof(AudioStreamBasicDescription), inAsbd);
          if (ps != noErr) {
            NSLog(@"ExtAudioFileSetProperty(ClientDataFormat mic) failed: %d",
                  (int)ps);
          }
          [input
              installTapOnBus:0
                   bufferSize:1024
                       format:inFormat
                        block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                          if (!g_micFile)
                            return;
                          OSStatus ws = ExtAudioFileWrite(
                              g_micFile, (UInt32)buffer.frameLength,
                              buffer.audioBufferList);
                          if (ws != noErr) {
                            NSLog(@"ExtAudioFileWrite mic failed: %d", (int)ws);
                          }
                        }];
          NSError *startErr = nil;
          [g_micEngine prepare];
          if (![g_micEngine startAndReturnError:&startErr]) {
            NSLog(@"mic engine start error: %@", startErr.localizedDescription);
          } else {
            NSLog(@"Mic capture started");
          }
        }
      }
    } @catch (NSException *ex) {
      NSLog(@"Mic start exception: %@", ex.reason);
    }

    g_isCapturing.store(true);
    return true;
  }
}

void sc_stop_capture() {
  @autoreleasepool {
    if (!g_isCapturing.load())
      return;
    g_isCapturing.store(false);
    if (g_stream) {
      [g_stream stopCaptureWithCompletionHandler:^(NSError *_Nullable error){
      }];
      g_stream = nil;
      NSLog(@"SCStream stopped");
    }
    if (g_audioFile) {
      ExtAudioFileDispose(g_audioFile);
      g_audioFile = NULL;
    }
    if (g_micEngine) {
      AVAudioInputNode *input = g_micEngine.inputNode;
      [input removeTapOnBus:0];
      [g_micEngine stop];
      g_micEngine = nil;
      NSLog(@"Mic capture stopped");
    }
    if (g_micFile) {
      ExtAudioFileDispose(g_micFile);
      g_micFile = NULL;
    }
    g_writer = nil;
    g_clientFormatSet.store(false);
  }
}

char *sc_list_input_devices() {
  @autoreleasepool {
    NSMutableArray *arr = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *session = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[
          AVCaptureDeviceTypeBuiltInMicrophone
        ]
                              mediaType:AVMediaTypeAudio
                               position:AVCaptureDevicePositionUnspecified];
    NSArray<AVCaptureDevice *> *devices = session.devices ?: @[];
    for (AVCaptureDevice *d in devices) {
      NSString *name = d.localizedName ?: @"";
      NSString *uid = d.uniqueID ?: @"";
      NSDictionary *item = @{@"id" : uid, @"name" : name, @"uniqueId" : uid};
      [arr addObject:item];
    }
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:arr
                                                   options:0
                                                     error:&err];
    NSString *s = nil;
    if (json) {
      s = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    } else {
      s = [NSString stringWithFormat:@"[{\"error\":\"%@\"}]",
                                     err.localizedDescription ?: @"unknown"];
    }
    const char *utf8 = [s UTF8String];
    size_t len = strlen(utf8);
    char *out = (char *)malloc(len + 1);
    memcpy(out, utf8, len + 1);
    return out;
  }
}
