#include "hello.h"
#include <cstdlib>
#include <cstring>
#include <string>

const char *hello_from_cpp() {
  std::string msg = "Hello from C++ 🎉";
  char *buf = (char *)std::malloc(msg.size() + 1);
  std::memcpy(buf, msg.c_str(), msg.size() + 1);
  return buf;
}

void free_str(const char *s) {
  if (s)
    std::free((void *)s);
}
