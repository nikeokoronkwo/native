// ignore_for_file: unused_element, unused_field

// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
// ignore_for_file: type=lint
import 'dart:ffi' as ffi;

/// Typedef Test
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

  NamedFunctionProto func1(
    NamedFunctionProto named,
    ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int)>> unnamed,
  ) {
    return _func1(
      named,
      unnamed,
    );
  }

  late final _func1Ptr = _lookup<
      ffi.NativeFunction<
          NamedFunctionProto Function(
              NamedFunctionProto,
              ffi.Pointer<
                  ffi.NativeFunction<ffi.Void Function(ffi.Int)>>)>>('func1');
  late final _func1 = _func1Ptr.asFunction<
      NamedFunctionProto Function(NamedFunctionProto,
          ffi.Pointer<ffi.NativeFunction<ffi.Void Function(ffi.Int)>>)>();

  void func2(
    ffi.Pointer<NTyperef1> arg0,
  ) {
    return _func2(
      arg0,
    );
  }

  late final _func2Ptr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<NTyperef1>)>>(
          'func2');
  late final _func2 =
      _func2Ptr.asFunction<void Function(ffi.Pointer<NTyperef1>)>();

  void func3(
    int arg0,
    int b,
  ) {
    return _func3(
      arg0,
      b,
    );
  }

  late final _func3Ptr = _lookup<
      ffi.NativeFunction<
          ffi.Void Function(ffi.IntPtr, NestingASpecifiedType)>>('func3');
  late final _func3 = _func3Ptr.asFunction<void Function(int, int)>();

  bool func4(
    ffi.Pointer<ffi.Bool> a,
  ) {
    return _func4(
      a,
    );
  }

  late final _func4Ptr =
      _lookup<ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.Bool>)>>(
          'func4');
  late final _func4 =
      _func4Ptr.asFunction<bool Function(ffi.Pointer<ffi.Bool>)>();
}

typedef NamedFunctionProtoFunction = ffi.Void Function();
typedef DartNamedFunctionProtoFunction = void Function();
typedef NamedFunctionProto
    = ffi.Pointer<ffi.NativeFunction<NamedFunctionProtoFunction>>;

final class Struct1 extends ffi.Struct {
  external NamedFunctionProto named;

  external ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> unnamed;
}

final class AnonymousStructInTypedef extends ffi.Opaque {}

typedef Typeref1 = AnonymousStructInTypedef;
typedef Typeref2 = AnonymousStructInTypedef;

final class _NamedStructInTypedef extends ffi.Opaque {}

typedef NamedStructInTypedef = _NamedStructInTypedef;

final class _ExcludedStruct extends ffi.Opaque {}

typedef ExcludedStruct = _ExcludedStruct;
typedef NTyperef1 = ExcludedStruct;

enum AnonymousEnumInTypedef {
  a(0);

  final int value;
  const AnonymousEnumInTypedef(this.value);

  static AnonymousEnumInTypedef fromValue(int value) => switch (value) {
        0 => a,
        _ => throw ArgumentError(
            'Unknown value for AnonymousEnumInTypedef: $value'),
      };
}

enum _NamedEnumInTypedef {
  b(0);

  final int value;
  const _NamedEnumInTypedef(this.value);

  static _NamedEnumInTypedef fromValue(int value) => switch (value) {
        0 => b,
        _ =>
          throw ArgumentError('Unknown value for _NamedEnumInTypedef: $value'),
      };
}

typedef NestingASpecifiedType = ffi.IntPtr;
typedef DartNestingASpecifiedType = int;

final class Struct2 extends ffi.Opaque {}

typedef Struct3 = Struct2;

final class WithBoolAlias extends ffi.Struct {
  @ffi.Bool()
  external bool b;
}

typedef IncludedTypedef = ffi.Pointer<ffi.Void>;
