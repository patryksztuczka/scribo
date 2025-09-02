#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Zwraca wskaźnik na napis (UTF-8).
// Pamięć trzeba zwolnić przez free_str.
const char *hello_from_cpp();

// Zwolnienie pamięci przydzielonej przez hello_from_cpp.
void free_str(const char *s);

#ifdef __cplusplus
}
#endif
