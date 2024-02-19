// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "native_add_library.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *foo_allocate() {
  // Allocate some resource.
  return calloc(1024, sizeof(char));
}

void foo_free(void *native_resource, char **err) {
  free(native_resource);
  const char *error_message = "Some error message.";
  *err = (char *)calloc(strlen(error_message) + 1, sizeof(char));
  strcpy(*err, error_message);
}

void foo_free_wrapper(void *native_resource) {
  char *err;
  foo_free(native_resource, &err);
  if (err != NULL) {
    // TODO: Use the Android / iOS Logging system here!
    printf("Error during finalization: %s\n", err);
  }
}
