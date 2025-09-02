#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Returns a UTF-8 encoded JSON string with available capture sources.
// The returned pointer must be freed by calling free_str (provided in
// hello.cpp).
const char *list_sources_json();

#ifdef __cplusplus
}
#endif
