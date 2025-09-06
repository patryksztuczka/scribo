#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Starts audio capture for the given source id.
// NOTE (macOS): We always capture application audio and save under
//   "~/Library/Application Support/scribo/capture-<timestamp>.wav".
// id: application PID or bundleId
// On error returns false and sets *out_err to a heap-allocated UTF-8 string
// (must call sc_free).
bool sc_start_capture(const char *id, char **out_err);

// Stops ongoing capture if any. Safe to call if not running.
void sc_stop_capture();

// Frees strings returned by sc_start_capture via out_err
void sc_free(char *s);

// Returns UTF-8 JSON array of input devices: [{ id, name, uniqueId }]
// Caller must free via sc_free.
char *sc_list_input_devices();

#ifdef __cplusplus
}
#endif
