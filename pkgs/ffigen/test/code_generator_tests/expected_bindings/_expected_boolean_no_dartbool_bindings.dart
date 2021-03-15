// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
import 'dart:ffi' as ffi;

class Bindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  Bindings(ffi.DynamicLibrary dynamicLibrary) : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  Bindings.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  int test1(
    int a,
    ffi.Pointer<ffi.Uint8> b,
  ) {
    return _test1(
      a,
      b,
    );
  }

  late final _test1_ptr = _lookup<ffi.NativeFunction<_c_test1>>('test1');
  late final _dart_test1 _test1 = _test1_ptr.asFunction<_dart_test1>();
}

class test2 extends ffi.Struct {
  @ffi.Uint8()
  external int a;
}

typedef _c_test1 = ffi.Uint8 Function(
  ffi.Uint8 a,
  ffi.Pointer<ffi.Uint8> b,
);

typedef _dart_test1 = int Function(
  int a,
  ffi.Pointer<ffi.Uint8> b,
);