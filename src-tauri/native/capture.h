#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Starts audio capture for given kind ("application" | "window" | "display")
// and id. id: for application -> PID or bundleId, for window -> windowID, for
// display -> displayID out_path: absolute path to output .wav On error returns
// false and sets *out_err to a heap-allocated UTF-8 string (must call sc_free).
bool sc_start_capture(const char *kind, const char *id, const char *out_path,
                      char **out_err);

// Stops ongoing capture if any. Safe to call if not running.
void sc_stop_capture();

// Frees strings returned by sc_start_capture via out_err
void sc_free(char *s);

#ifdef __cplusplus
}
#endif
