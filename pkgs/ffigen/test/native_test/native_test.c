// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
#define aloc(T) ((T *)malloc(sizeof(T)))

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>

bool Function1Bool(bool x) { return !x; }

uint8_t Function1Uint8(uint8_t x) { return x + 42; }

uint16_t Function1Uint16(uint16_t x) { return x + 42; }

uint32_t Function1Uint32(uint32_t x) { return x + 42; }

uint64_t Function1Uint64(uint64_t x) { return x + 42; }

int8_t Function1Int8(int8_t x) { return x + 42; }

int16_t Function1Int16(int16_t x) { return x + 42; }

int32_t Function1Int32(int32_t x) { return x + 42; }

int64_t Function1Int64(int64_t x) { return x + 42; }

intptr_t Function1IntPtr(intptr_t x) { return x + 42; }

uintptr_t Function1UintPtr(uintptr_t x) { return x + 42; }

float Function1Float(float x) { return x + 42.0f; }

double Function1Double(double x) { return x + 42.0; }

struct Struct1
{
    int8_t a;
    int32_t data[3][1][2];
};

struct Struct1 *getStruct1()
{
    struct Struct1 *s = aloc(struct Struct1);
    s->a = 0;
    s->data[0][0][0] = 1;
    s->data[0][0][1] = 2;
    s->data[1][0][0] = 3;
    s->data[1][0][1] = 4;
    s->data[2][0][0] = 5;
    s->data[2][0][1] = 6;
    return s;
}

struct Struct3
{
    int a;
    int b;
    int c;
};

struct Struct3 Function1StructReturnByValue(int a, int b, int c)
{
    struct Struct3 s;
    s.a = a;
    s.b = b;
    s.c = c;
    return s;
}

int Function1StructPassByValue(struct Struct3 sum_a_b_c)
{
    return sum_a_b_c.a + sum_a_b_c.b + sum_a_b_c.c;
}

//  ===== Enum tests =====

typedef enum Enum1 {
  enum1Value1,
  enum1Value2,
  enum1Value3,
} Enum1;

typedef enum Enum2 {
  enum2Value1,
  enum2Value2,
  enum2Value3,
} Enum2;

typedef struct StructWithEnums {
  Enum1 enum1;
  Enum1 enum1Array[5];
  Enum1* enum1Pointer;

  Enum2 enum2;
  Enum2 enum2Array[5];
  Enum2* enum2Pointer;
} StructWithEnums;

Enum1 funcWithEnum1(Enum1 value) { return value; }
Enum2 funcWithEnum2(Enum2 value) { return value; }
StructWithEnums getStructWithEnums() {
    StructWithEnums s;
    s.enum1 = enum1Value1;
    s.enum1Pointer = aloc(Enum1);
    *s.enum1Pointer = enum1Value2;
    for (int i = 0; i < 5; i++) {
        s.enum1Array[i] = enum1Value3;
    }
    s.enum2 = enum2Value1;
    s.enum2Pointer = aloc(Enum2);
    *s.enum2Pointer = enum2Value2;
    for (int i = 0; i < 5; i++) {
        s.enum2Array[i] = enum2Value3;
    }
    return s;
}

int globalArray[3];
