// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "native_add_library.h"

#include <stdio.h>

int32_t add(int32_t a, int32_t b) {
  printf("Adding %i and %i.\n", a, b);
  return a + b;
}

void the_finalizer(void *native_resource, char **err) {
  free(native_resource);
  const char *error_message = "error";
  *err = (char *)calloc(strlen(error_message) + 1, sizeof(char));
  strcpy(*err, error_message);
}

void finalizer_wrapper(struct FinalizerHelper *helper) {
  char *err;
  the_finalizer(helper->thing_to_free, &err);
  if (err != NULL) {
    printf("Calling callback from C (might not run if isolate is already shut "
           "down).\n");
    helper->callback(err);
  }
  free(helper);
}
