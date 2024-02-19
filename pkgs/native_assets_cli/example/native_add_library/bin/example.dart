import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:native_add_library/native_add_library.dart';

void main() async {
  allocateFinalizablesAndForgetAboutThem();
  for (int i = 0; i < 10; i++) {
    forceDartGcToRun();
    await Future.delayed(Duration(milliseconds: 100));
  }
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
  static final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
      _finalizerFunction = Native.addressOf(foo_free_wrapper);

  static final finalizer = NativeFinalizer(_finalizerFunction.cast());

  MyFinalizable() {
    final nativeBuffer = foo_allocate();
    finalizer.attach(this, nativeBuffer.cast());
  }
}
