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
static NSString *g_lastOutPath = nil; // full path to app wav

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

bool sc_start_capture(const char *id, char **out_err) {
  @autoreleasepool {
    if (!id) {
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

    NSString *idStr = [NSString stringWithUTF8String:id];
    // Build fixed base dir: ~/Library/Application Support/scribo
    NSString *home = NSHomeDirectory();
    NSString *baseDir = [home
        stringByAppendingPathComponent:@"Library/Application Support/scribo"];
    // Ensure base dir exists
    NSError *mkErr = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:baseDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkErr];
    if (mkErr) {
      if (out_err)
        *out_err = dup_cstr([[NSString
            stringWithFormat:@"mkdir failed: %@",
                             mkErr.localizedDescription ?: @"unknown"]
            UTF8String]);
      return false;
    }
    NSString *path = [baseDir
        stringByAppendingPathComponent:
            [NSString
                stringWithFormat:@"capture-%@.wav",
                                 @((long long)(
                                     [[NSDate date] timeIntervalSince1970] *
                                     1000))]];
    if (g_lastOutPath) {
      g_lastOutPath = nil;
    }
    g_lastOutPath = [path copy];

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

    // Always capture application audio (id = PID or bundleId)
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
    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:disp
                                                 includingApplications:@[ app ]
                                                      exceptingWindows:@[]];

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
    // Offline mix app + mic into -mix.wav
    @try {
      if (g_lastOutPath) {
        NSString *baseNoExt = [g_lastOutPath stringByDeletingPathExtension];
        NSString *appPath = g_lastOutPath;
        NSString *micPath = [baseNoExt stringByAppendingString:@"-mic.wav"];
        NSString *mixPath = [baseNoExt stringByAppendingString:@"-mix.wav"];

        // Open inputs
        ExtAudioFileRef appIn = NULL, micIn = NULL, outFile = NULL;
        CFURLRef appUrl = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
        CFURLRef micUrl = (__bridge CFURLRef)[NSURL fileURLWithPath:micPath];
        OSStatus stA = ExtAudioFileOpenURL(appUrl, &appIn);
        OSStatus stM = ExtAudioFileOpenURL(micUrl, &micIn);
        if (stA != noErr || stM != noErr || !appIn || !micIn) {
          NSLog(@"mix: open inputs failed %d %d", (int)stA, (int)stM);
          if (appIn)
            ExtAudioFileDispose(appIn);
          if (micIn)
            ExtAudioFileDispose(micIn);
        } else {
          // Set client formats for reading (Float32 interleaved)
          AudioStreamBasicDescription readApp = {0};
          readApp.mSampleRate = 48000.0;
          readApp.mFormatID = kAudioFormatLinearPCM;
          readApp.mFormatFlags =
              kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
          readApp.mFramesPerPacket = 1;
          readApp.mChannelsPerFrame = 2; // app in stereo
          readApp.mBitsPerChannel = 32;
          readApp.mBytesPerFrame =
              (readApp.mBitsPerChannel / 8) * readApp.mChannelsPerFrame;
          readApp.mBytesPerPacket =
              readApp.mBytesPerFrame * readApp.mFramesPerPacket;

          AudioStreamBasicDescription readMic = {0};
          readMic.mSampleRate = 48000.0;
          readMic.mFormatID = kAudioFormatLinearPCM;
          readMic.mFormatFlags =
              kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
          readMic.mFramesPerPacket = 1;
          readMic.mChannelsPerFrame = 1; // downmix mic to mono
          readMic.mBitsPerChannel = 32;
          readMic.mBytesPerFrame =
              (readMic.mBitsPerChannel / 8) * readMic.mChannelsPerFrame;
          readMic.mBytesPerPacket =
              readMic.mBytesPerFrame * readMic.mFramesPerPacket;

          ExtAudioFileSetProperty(appIn, kExtAudioFileProperty_ClientDataFormat,
                                  sizeof(readApp), &readApp);
          ExtAudioFileSetProperty(micIn, kExtAudioFileProperty_ClientDataFormat,
                                  sizeof(readMic), &readMic);

          // First pass: measure RMS for app and mic
          const UInt32 kFrames = 4096;
          UInt32 appBufBytes1 = kFrames * readApp.mBytesPerFrame;
          UInt32 micBufBytes1 = kFrames * readMic.mBytesPerFrame;
          float *appBuf1 = (float *)malloc(appBufBytes1);
          float *micBuf1 = (float *)malloc(micBufBytes1);
          AudioBufferList appAbl1;
          appAbl1.mNumberBuffers = 1;
          appAbl1.mBuffers[0].mNumberChannels = readApp.mChannelsPerFrame;
          appAbl1.mBuffers[0].mDataByteSize = appBufBytes1;
          appAbl1.mBuffers[0].mData = appBuf1;
          AudioBufferList micAbl1;
          micAbl1.mNumberBuffers = 1;
          micAbl1.mBuffers[0].mNumberChannels = readMic.mChannelsPerFrame;
          micAbl1.mBuffers[0].mDataByteSize = micBufBytes1;
          micAbl1.mBuffers[0].mData = micBuf1;
          double appSumSq = 0.0, micSumSq = 0.0;
          uint64_t appCount = 0, micCount = 0;
          while (1) {
            UInt32 framesA = kFrames, framesM = kFrames;
            OSStatus ra = ExtAudioFileRead(appIn, &framesA, &appAbl1);
            OSStatus rm = ExtAudioFileRead(micIn, &framesM, &micAbl1);
            if (ra != noErr || rm != noErr) {
              break;
            }
            if (framesA == 0 && framesM == 0)
              break;
            for (UInt32 i = 0; i < framesA; ++i) {
              float L = appBuf1[i * 2 + 0];
              float R = appBuf1[i * 2 + 1];
              float m = 0.5f * (L + R);
              appSumSq += (double)m * (double)m;
            }
            appCount += framesA;
            for (UInt32 i = 0; i < framesM; ++i) {
              float s = micBuf1[i];
              micSumSq += (double)s * (double)s;
            }
            micCount += framesM;
          }
          double appRms =
              (appCount > 0) ? sqrt(appSumSq / (double)appCount) : 0.0;
          double micRms =
              (micCount > 0) ? sqrt(micSumSq / (double)micCount) : 0.0;
          if (appBuf1)
            free(appBuf1);
          if (micBuf1)
            free(micBuf1);
          ExtAudioFileDispose(appIn);
          appIn = NULL;
          ExtAudioFileDispose(micIn);
          micIn = NULL;

          // Reopen inputs for mixing pass
          stA = ExtAudioFileOpenURL(appUrl, &appIn);
          stM = ExtAudioFileOpenURL(micUrl, &micIn);
          if (stA != noErr || stM != noErr || !appIn || !micIn) {
            NSLog(@"mix: reopen inputs failed %d %d", (int)stA, (int)stM);
          } else {
            ExtAudioFileSetProperty(appIn,
                                    kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(readApp), &readApp);
            ExtAudioFileSetProperty(micIn,
                                    kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(readMic), &readMic);

            // Create output (Int16 stereo)
            AudioStreamBasicDescription outAsbd = {0};
            outAsbd.mSampleRate = 48000.0;
            outAsbd.mFormatID = kAudioFormatLinearPCM;
            outAsbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger |
                                   kLinearPCMFormatFlagIsPacked;
            outAsbd.mFramesPerPacket = 1;
            outAsbd.mChannelsPerFrame = 2;
            outAsbd.mBitsPerChannel = 16;
            outAsbd.mBytesPerFrame =
                (outAsbd.mBitsPerChannel / 8) * outAsbd.mChannelsPerFrame;
            outAsbd.mBytesPerPacket =
                outAsbd.mBytesPerFrame * outAsbd.mFramesPerPacket;

            CFURLRef outUrl =
                (__bridge CFURLRef)[NSURL fileURLWithPath:mixPath];
            OSStatus stO = ExtAudioFileCreateWithURL(
                outUrl, kAudioFileWAVEType, &outAsbd, NULL,
                kAudioFileFlags_EraseFile, &outFile);
            if (stO != noErr || !outFile) {
              NSLog(@"mix: create out failed %d", (int)stO);
            } else {
              // Compute per-source gains: gently lift quieter source
              float appGain = 1.0f, micGain = 1.0f;
              if (appRms > 0.0 && micRms > 0.0) {
                double ratio = micRms / appRms; // if app is quieter, ratio > 1
                if (ratio < 0.5)
                  ratio = 0.5; // -6 dB min
                if (ratio > 2.0)
                  ratio = 2.0;                 // +6 dB max
                appGain = (float)ratio * 0.8f; // modest boost with padding
              }
              // Soften mic a bit
              micGain = 0.6f;
              // Extra headroom
              const float postAtten = 0.6f;

              const UInt32 kFrames2 = 2048;
              UInt32 appBufBytes = kFrames2 * readApp.mBytesPerFrame;
              UInt32 micBufBytes = kFrames2 * readMic.mBytesPerFrame;
              float *appBuf = (float *)malloc(appBufBytes);
              float *micBuf = (float *)malloc(micBufBytes);
              UInt32 outBufBytes = kFrames2 * outAsbd.mBytesPerFrame;
              int16_t *outBuf = (int16_t *)malloc(outBufBytes);

              AudioBufferList appAbl;
              appAbl.mNumberBuffers = 1;
              appAbl.mBuffers[0].mNumberChannels = readApp.mChannelsPerFrame;
              appAbl.mBuffers[0].mDataByteSize = appBufBytes;
              appAbl.mBuffers[0].mData = appBuf;
              AudioBufferList micAbl;
              micAbl.mNumberBuffers = 1;
              micAbl.mBuffers[0].mNumberChannels = readMic.mChannelsPerFrame;
              micAbl.mBuffers[0].mDataByteSize = micBufBytes;
              micAbl.mBuffers[0].mData = micBuf;
              AudioBufferList outAbl;
              outAbl.mNumberBuffers = 1;
              outAbl.mBuffers[0].mNumberChannels = outAsbd.mChannelsPerFrame;
              outAbl.mBuffers[0].mDataByteSize = outBufBytes;
              outAbl.mBuffers[0].mData = outBuf;

              while (1) {
                UInt32 framesA = kFrames2;
                UInt32 framesM = kFrames2;
                OSStatus ra2 = ExtAudioFileRead(appIn, &framesA, &appAbl);
                OSStatus rm2 = ExtAudioFileRead(micIn, &framesM, &micAbl);
                if (ra2 != noErr || rm2 != noErr) {
                  NSLog(@"mix: read err %d %d", (int)ra2, (int)rm2);
                  break;
                }
                if (framesA == 0 && framesM == 0)
                  break;
                UInt32 frames = framesA > framesM ? framesA : framesM;
                for (UInt32 i = 0; i < frames; ++i) {
                  float appL = 0.0f, appR = 0.0f;
                  if (i < framesA) {
                    appL = appBuf[i * 2 + 0];
                    appR = appBuf[i * 2 + 1];
                  }
                  float micS = 0.0f;
                  if (i < framesM) {
                    micS = micBuf[i];
                  }
                  float outL = (appL * appGain + micS * micGain) * postAtten;
                  float outR = (appR * appGain + micS * micGain) * postAtten;
                  if (outL > 1.0f)
                    outL = 1.0f;
                  if (outL < -1.0f)
                    outL = -1.0f;
                  if (outR > 1.0f)
                    outR = 1.0f;
                  if (outR < -1.0f)
                    outR = -1.0f;
                  outBuf[i * 2 + 0] = (int16_t)(outL * 32767.0f);
                  outBuf[i * 2 + 1] = (int16_t)(outR * 32767.0f);
                }
                outAbl.mBuffers[0].mDataByteSize =
                    frames * outAsbd.mBytesPerFrame;
                OSStatus wr = ExtAudioFileWrite(outFile, frames, &outAbl);
                if (wr != noErr) {
                  NSLog(@"mix: write err %d", (int)wr);
                  break;
                }
              }

              if (appBuf)
                free(appBuf);
              if (micBuf)
                free(micBuf);
              if (outBuf)
                free(outBuf);
            }
            if (outFile)
              ExtAudioFileDispose(outFile);
          }
          if (appIn)
            ExtAudioFileDispose(appIn);
          if (micIn)
            ExtAudioFileDispose(micIn);
        }
        // If mix file exists and is non-empty, remove the partial inputs
        @try {
          NSFileManager *fm = [NSFileManager defaultManager];
          NSError *attrErr = nil;
          NSDictionary<NSFileAttributeKey, id> *attrs =
              [fm attributesOfItemAtPath:mixPath error:&attrErr];
          if (attrs && [attrs fileSize] > 0) {
            NSError *rmErrA = nil;
            if ([fm fileExistsAtPath:appPath]) {
              [fm removeItemAtPath:appPath error:&rmErrA];
              if (rmErrA) {
                NSLog(@"remove appPath failed: %@",
                      rmErrA.localizedDescription);
              }
            }
            NSError *rmErrM = nil;
            if ([fm fileExistsAtPath:micPath]) {
              [fm removeItemAtPath:micPath error:&rmErrM];
              if (rmErrM) {
                NSLog(@"remove micPath failed: %@",
                      rmErrM.localizedDescription);
              }
            }
          }
        } @catch (NSException *ex) {
          NSLog(@"cleanup exception: %@", ex.reason);
        }
      }
    } @catch (NSException *ex) {
      NSLog(@"mix exception: %@", ex.reason);
    }
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
