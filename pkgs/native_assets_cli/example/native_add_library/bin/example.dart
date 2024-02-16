import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:native_add_library/native_add_library.dart';

void main() async {
  allocateFinalizablesAndForgetAboutThem();
  for (int i = 0; i < 10; i++) {
    print(i);
    forceDartGcToRun();
    await Future.delayed(Duration(milliseconds: 100));
  }
  errorPrinter.close(); // otherwise we don't exit
  print('Exiting main isolate');
}

@pragma('vm:never-inline')
void allocateFinalizablesAndForgetAboutThem() {
  for (int i = 0; i < 3; i++) {
    MyFinalizable();
  }
}

@pragma('vm:never-inline')
void forceDartGcToRun() {
  for (int i = 0; i < 1000; i++) {
    Uint8List(1000);
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
    finalizer.attach(this, finalizerToken.cast());
  }
}

final errorPrinter =
    NativeCallable<Void Function(Pointer<Char>)>.listener(printError);

void printError(Pointer<Char> error) {
  print('printError');
  print(error.cast<Utf8>().toDartString());
  calloc.free(error);
}
