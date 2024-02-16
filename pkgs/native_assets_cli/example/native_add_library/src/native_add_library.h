// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if _WIN32
#define MYLIB_EXPORT extern "C" __declspec(dllexport)
#else
#define MYLIB_EXPORT extern "C"
#endif

MYLIB_EXPORT int32_t add(int32_t a, int32_t b);

struct FinalizerHelper {
  void *thing_to_free;
  void (*callback)(char *);
};

MYLIB_EXPORT void finalizer_wrapper(struct FinalizerHelper *helper);
