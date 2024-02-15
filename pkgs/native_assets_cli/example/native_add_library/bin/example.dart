import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:native_add_library/native_add_library.dart';

void main() async {
  print('foo');

  print('bar');
  await Future.delayed(Duration(seconds: 1));
  await Future.delayed(Duration(seconds: 1));
  await Future.delayed(Duration(seconds: 1));
  errorPrinter.close(); // otherwise we don't exit
}

void bla() {
  for (int i = 0; i < 10; i++) {
    final myFinalizable = MyFinalizable();
  }
}

class MyFinalizable implements Finalizable {
  static final Pointer<NativeFunction<Void Function(Pointer<FinalizerHelper>)>>
      _finalizerFunction = Native.addressOf(finalizer_wrapper);
  static final finalizer = NativeFinalizer(_finalizerFunction.cast());

  MyFinalizable() {
    final finalizerToken = calloc<FinalizerHelper>();
    final nativeBuffer = calloc<Int8>(1024);
    finalizerToken.ref.thing_to_free = nativeBuffer.cast();
    finalizerToken.ref.callback = errorPrinter.nativeFunction;
  }
}

final errorPrinter =
    NativeCallable<Void Function(Pointer<Char>)>.listener(printError);

void printError(Pointer<Char> error) {
  print(error.cast<Utf8>().toDartString());
  calloc.free(error);
}
