// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <iostream>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if _WIN32
#define MYLIB_EXPORT __declspec(dllexport)
#else
#define MYLIB_EXPORT
#endif

MYLIB_EXPORT int32_t add(int32_t a, int32_t b);

struct FinalizerHelper {
  void *thing_to_free;
  void (*callback)(char *);
};

void the_finalizer(void *native_resource, char **err) {
  free(native_resource);
  strcpy(*err, "error");
}

void finalizer_wrapper(struct FinalizerHelper *helper) {
  std::cout << "finalizer_wrapper\n";
  char *err;
  the_finalizer(helper->thing_to_free, &err);
  if (err != NULL) {
    std::cout << "calling callback from C\n";
    helper->callback(err);
  }
  free(helper);
}
