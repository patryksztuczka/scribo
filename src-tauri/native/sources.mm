#import "sources.h"
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <cstdlib>
#include <cstring>
#import <dispatch/dispatch.h>

static char *make_c_string_from_nsstring(NSString *str) {
  if (str == nil) {
    str = @"";
  }
  NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) {
    const char *fallback = "";
    size_t len = std::strlen(fallback);
    char *buf = (char *)std::malloc(len + 1);
    std::memcpy(buf, fallback, len + 1);
    return buf;
  }
  size_t len = [data length];
  char *buf = (char *)std::malloc(len + 1);
  std::memcpy(buf, [data bytes], len);
  buf[len] = '\0';
  return buf;
}

static NSString *screenNameForDisplayID(uint32_t displayID)
    API_AVAILABLE(macos(10.15)) {
  for (NSScreen *screen in [NSScreen screens]) {
    NSNumber *num = [screen.deviceDescription objectForKey:@"NSScreenNumber"];
    if (num && [num unsignedIntValue] == displayID) {
      if ([screen respondsToSelector:@selector(localizedName)]) {
        return screen.localizedName;
      }
      return [NSString stringWithFormat:@"Display %u", displayID];
    }
  }
  return [NSString stringWithFormat:@"Display %u", displayID];
}

const char *list_sources_json() {
  @autoreleasepool {
    if (@available(macOS 12.3, *)) {
      __block SCShareableContent *content = nil;
      __block NSError *fetchError = nil;
      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
      [SCShareableContent
          getShareableContentWithCompletionHandler:^(
              SCShareableContent *_Nullable c, NSError *_Nullable error) {
            content = c;
            fetchError = error;
            dispatch_semaphore_signal(sema);
          }];
      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

      if (fetchError != nil || content == nil) {
        NSString *err = fetchError ? fetchError.localizedDescription
                                   : @"shareableContent nil";
        NSString *json = [NSString stringWithFormat:@"{\"error\":\"%@\"}", err];
        return make_c_string_from_nsstring(json);
      }

      NSMutableArray *displays = [NSMutableArray array];
      for (SCDisplay *d in content.displays) {
        uint32_t did = d.displayID;
        NSString *name = screenNameForDisplayID(did);
        NSDictionary *item = @{@"id" : @(did), @"name" : name ?: @""};
        [displays addObject:item];
      }

      NSMutableArray *windows = [NSMutableArray array];
      for (SCWindow *w in content.windows) {
        NSString *title = w.title ?: @"";
        SCRunningApplication *app = w.owningApplication;
        NSNumber *pid = app ? @(app.processID) : @(0);
        NSString *appName = app.applicationName ?: @"";
        NSDictionary *item = @{
          @"id" : @(w.windowID),
          @"title" : title,
          @"appName" : appName,
          @"pid" : pid
        };
        [windows addObject:item];
      }

      NSMutableArray *applications = [NSMutableArray array];
      for (SCRunningApplication *a in content.applications) {
        NSString *name = a.applicationName ?: @"";
        NSString *bundleId = a.bundleIdentifier ?: @"";
        NSDictionary *item =
            @{@"pid" : @(a.processID),
              @"name" : name,
              @"bundleId" : bundleId};
        [applications addObject:item];
      }

      NSDictionary *result = @{
        @"displays" : displays,
        @"windows" : windows,
        @"applications" : applications
      };
      NSError *err = nil;
      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                         options:0
                                                           error:&err];
      if (!jsonData) {
        NSString *json = [NSString
            stringWithFormat:@"{\"error\":\"serialization_failed:%@\"}",
                             err.localizedDescription ?: @"unknown"];
        return make_c_string_from_nsstring(json);
      }
      NSString *json = [[NSString alloc] initWithData:jsonData
                                             encoding:NSUTF8StringEncoding];
      return make_c_string_from_nsstring(json);
    } else {
      NSString *json =
          @"{\"error\":\"Requires macOS 12.3+ for ScreenCaptureKit\"}";
      return make_c_string_from_nsstring(json);
    }
  }
}
