// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:jni/_internal.dart';
import 'package:jni/jni.dart';
import 'package:test/test.dart';

import '../test_util/callback_types.dart';
import 'bindings/simple_package.dart';

const pi = 3.14159;
const fpDelta = 0.001;
const trillion = 1024 * 1024 * 1024 * 1024;

void _runJavaGC() {
  final managementFactory = JClass.forName(
    'java/lang/management/ManagementFactory',
  );
  final bean = managementFactory
      .staticMethodId(
    'getRuntimeMXBean',
    '()Ljava/lang/management/RuntimeMXBean;',
  )
      .call(managementFactory, JObject.type, []);
  final pid =
      bean.jClass.instanceMethodId('getPid', '()J').call(bean, jlong.type, []);
  ProcessResult result;
  do {
    result = Process.runSync('jcmd', [pid.toString(), 'GC.run']);
    sleep(const Duration(milliseconds: 100));
  } while (result.exitCode != 0);
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 8; ++i) {
    await Future<void>.delayed(Duration(milliseconds: (1 << i) * 100));
    if (predicate()) {
      return;
    }
  }
}

void registerTests(String groupName, TestRunnerCallback test) {
  group(groupName, () {
    test('static final fields - int', () {
      expect(Example.ON, equals(1));
      expect(Example.OFF, equals(0));
      expect(Example.PI, closeTo(pi, fpDelta));
      expect(Example.SEMICOLON, equals(';'.codeUnitAt(0)));
      expect(
        Example.SEMICOLON_STRING!.toDartString(releaseOriginal: true),
        equals(';'),
      );
    });

    test('Static methods - primitive', () {
      // same test can be run at a replicated (dart-only) test, check for both
      // possible values.
      expect(Example.getAmount(), isIn([1012, 500]));
      Example.setAmount(1012);
      expect(Example.getAmount(), equals(1012));
      expect(Example.getAsterisk(), equals('*'.codeUnitAt(0)));
      expect(C2.CONSTANT, equals(12));
    });

    test('Static fields & methods - string', () {
      expect(
        Example.getName()!.toDartString(releaseOriginal: true),
        isIn(['Ragnar Lothbrok', 'Theseus']),
      );
      Example.setName('Theseus'.toJString());
      expect(
        Example.getName()!.toDartString(releaseOriginal: true),
        equals('Theseus'),
      );
    });

    test('Static fields and methods - Object', () {
      final nested = Example.getNestedInstance()!;
      expect(nested.getValue(), isIn([true, false]));
      nested.setValue(false);
      expect(nested.getValue(), isFalse);
    });

    test('static methods with several arguments', () {
      expect(Example.addInts(10, 15), equals(25));
      expect(Example.max4(-1, 15, 30, 12), equals(30));
      expect(Example.max8(1, 4, 8, 2, 4, 10, 8, 6), equals(10));
    });

    test('Instance methods (getters & setters)', () {
      final e = Example();
      expect(e.getNumber(), equals(0));
      expect(e.getIsUp(), true);
      expect(e.getCodename()!.toDartString(), equals('achilles'));
      e.setNumber(1);
      e.setUp(false);
      e.setCodename('spartan'.toJString());
      expect(e.getIsUp(), false);
      expect(e.getNumber(), 1);
      expect(e.getCodename()!.toDartString(), equals('spartan'));
      e.release();
    });

    test('Instance methods with several arguments', () {
      final e = Example();
      expect(e.add4Longs(1, 2, 3, 4), equals(10));
      expect(e.add8Longs(1, 1, 2, 2, 3, 3, 12, 24), equals(48));
      expect(
        e.add4Longs(trillion, trillion, trillion, trillion),
        equals(4 * trillion),
      );
      expect(
        e.add8Longs(
          trillion,
          -trillion,
          trillion,
          -trillion,
          trillion,
          -trillion,
          -trillion,
          -trillion,
        ),
        equals(2 * -trillion),
      );
      e.release();
    });

    test('Misc. instance methods', () {
      final e = Example();
      final rand = e.getRandom();
      expect(rand, isNotNull);
      final _ = e.getRandomLong();
      final id =
          e.getRandomNumericString(rand)!.toDartString(releaseOriginal: true);
      expect(int.parse(id), lessThan(10000));
      e.setNumber(145);
      expect(
        e.getSelf()!.getSelf()!.getSelf()!.getSelf()!.getNumber(),
        equals(145),
      );
      e.release();
    });

    test('Constructors', () {
      final e0 = Example();
      expect(e0.getNumber(), 0);
      expect(e0.getIsUp(), true);
      expect(e0.getCodename()!.toDartString(), equals('achilles'));
      final e1 = Example.new$1(111);
      expect(e1.getNumber(), equals(111));
      expect(e1.getIsUp(), true);
      expect(e1.getCodename()!.toDartString(), 'achilles');
      final e2 = Example.new$2(122, false);
      expect(e2.getNumber(), equals(122));
      expect(e2.getIsUp(), false);
      expect(e2.getCodename()!.toDartString(), 'achilles');
      final e3 = Example.new$3(133, false, 'spartan'.toJString());
      expect(e3.getNumber(), equals(133));
      expect(e3.getIsUp(), false);
      expect(e3.getCodename()!.toDartString(), 'spartan');
    });

    test('Static (non-final) fields', () {
      // Other replica test may already have modified this, so assert both
      // values.
      expect(Fields.amount, isIn([500, 101]));
      Fields.amount = 101;
      expect(Fields.amount, equals(101));

      expect(Fields.asterisk, equals('*'.codeUnitAt(0)));

      expect(
        Fields.name!.toDartString(),
        isIn(['Earl Haraldson', 'Ragnar Lothbrok']),
      );

      Fields.name = 'Ragnar Lothbrok'.toJString();
      expect(Fields.name!.toDartString(), equals('Ragnar Lothbrok'));

      expect(Fields.pi, closeTo(pi, fpDelta));
    });

    test('Instance fields', () {
      final f = Fields();
      expect(f.trillion, equals(trillion));

      expect(f.isAchillesDead, isFalse);
      expect(f.bestFighterInGreece!.toDartString(), equals('Achilles'));
      // "For your glory walks hand-in-hand with your doom." - Thetis.
      f.isAchillesDead = true;
      // I don't know much Greek mythology. But Troy was released in 2004,
      // and 300 was released in 2006, so it's Leonidas I.
      f.bestFighterInGreece = 'Leonidas I'.toJString();
      expect(f.isAchillesDead, isTrue);
      expect(f.bestFighterInGreece!.toDartString(), 'Leonidas I');
    });

    test('Fields from nested class', () {
      expect(Fields$Nested().hundred, equals(100));
      // Hector of Troy may disagree.
      expect(Fields$Nested.BEST_GOD!.toDartString(), equals('Pallas Athena'));
    });

    test('static methods arrays', () {
      final array = Example.getArr()!;
      expect(array[0], 1);
      expect(array[1], 2);
      expect(array[2], 3);
      expect(Example.addAll(array), 6);
      array[0] = 4;
      expect(Example.addAll(array), 9);
    });

    test('array of the class', () {
      final ex1 = Example();
      final ex2 = Example();
      ex1.setNumber(1);
      ex2.setNumber(2);
      final array = JArray(Example.nullableType, 2);
      array[0] = ex1;
      array[1] = ex2;
      expect(array[0]!.getNumber(), 1);
      expect(array[1]!.getNumber(), 2);
      array.release();
      ex1.release();
      ex2.release();
    });

    test('Check bindings for same-named classes', () {
      expect(Example().whichExample(), 0);
      expect(Example$1().whichExample(), 1);
    });

    test('Unicode char', () {
      expect(Fields.euroSymbol, equals('\u20AC'.codeUnitAt(0)));
    });

    group('exception tests', () {
      void throwsException(void Function() f) {
        expect(f, throwsA(isA<JniException>()));
      }

      test('Example throw exception', () {
        throwsException(Example.throwException);
      });

      test('Exception from method returning Object', () {
        throwsException(Exceptions.staticObjectMethod);
        throwsException(Exceptions.staticObjectArrayMethod);
        final x = Exceptions();
        throwsException(x.objectMethod);
        throwsException(x.objectArrayMethod);
      });

      test('Exception from method returning int', () {
        throwsException(Exceptions.staticIntMethod);
        throwsException(Exceptions.staticIntArrayMethod);
        final x = Exceptions();
        throwsException(x.intMethod);
        throwsException(x.intArrayMethod);
      });

      test('Exception from constructor', () {
        throwsException(() => Exceptions.new$1(6.8));
        throwsException(() => Exceptions.new$2(1, 2, 3, 4, 5, 6));
      });

      test('Exception contains error message & stack trace', () {
        try {
          Exceptions.throwLoremIpsum();
        } on JniException catch (e) {
          expect(e.message, stringContainsInOrder(['Lorem Ipsum']));
          expect(
            e.toString(),
            stringContainsInOrder(['Lorem Ipsum', 'throwLoremIpsum']),
          );
          return;
        }
        throw AssertionError('No exception was thrown');
      });
    });

    group('generics', () {
      test('GrandParent constructor', () {
        using((arena) {
          final grandParent = GrandParent(
            'Hello'.toJString()..releasedBy(arena),
            T: JString.type,
          )..releasedBy(arena);
          expect(grandParent, isA<GrandParent<JString>>());
          expect(grandParent.$type, isA<$GrandParent$Type<JString>>());
          expect(
            grandParent.value!.toDartString(releaseOriginal: true),
            'Hello',
          );
        });
      });
      test('MyStack<T>', () {
        using((arena) {
          final stack = MyStack(T: JString.type)..releasedBy(arena);
          stack.push('Hello'.toJString()..releasedBy(arena));
          stack.push('World'.toJString()..releasedBy(arena));
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'World');
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'Hello');
        });
      });
      test(
        'Different stacks have different types, same stacks have same types',
        () {
          using((arena) {
            final aStringStack = MyStack(T: JString.type)..releasedBy(arena);
            final anotherStringStack = MyStack(T: JString.type)
              ..releasedBy(arena);
            final anObjectStack = MyStack(T: JObject.type)..releasedBy(arena);
            expect(aStringStack.$type, anotherStringStack.$type);
            expect(
              aStringStack.$type.hashCode,
              anotherStringStack.$type.hashCode,
            );
            expect(aStringStack.$type, isNot(anObjectStack.$type));
            expect(
              aStringStack.$type.hashCode,
              isNot(anObjectStack.$type.hashCode),
            );
          });
        },
      );
      test('MyMap<K, V>', () {
        using((arena) {
          final map = MyMap(K: JString.type, V: Example.type)
            ..releasedBy(arena);
          final helloExample = Example.new$1(1)..releasedBy(arena);
          final worldExample = Example.new$1(2)..releasedBy(arena);
          map.put('Hello'.toJString()..releasedBy(arena), helloExample);
          map.put('World'.toJString()..releasedBy(arena), worldExample);
          expect(
            (map.get('Hello'.toJString()..releasedBy(arena))!
                  ..releasedBy(arena))
                .getNumber(),
            1,
          );
          expect(
            (map.get('World'.toJString()..releasedBy(arena))!
                  ..releasedBy(arena))
                .getNumber(),
            2,
          );
          expect(
            ((map.entryStack()!..releasedBy(arena)).pop()!..releasedBy(arena))
                .key!
                .as(JString.type, releaseOriginal: true)
                .toDartString(releaseOriginal: true),
            anyOf('Hello', 'World'),
          );
        });
      });
      group('classes extending generics', () {
        test('StringStack', () {
          using((arena) {
            final stringStack = StringStack()..releasedBy(arena);
            stringStack.push('Hello'.toJString()..releasedBy(arena));
            expect(
              stringStack.pop()!.toDartString(releaseOriginal: true),
              'Hello',
            );
          });
        });
        test('StringKeyedMap', () {
          using((arena) {
            final map = StringKeyedMap(V: Example.type)..releasedBy(arena);
            final example = Example()..releasedBy(arena);
            map.put('Hello'.toJString()..releasedBy(arena), example);
            expect(
              (map.get('Hello'.toJString()..releasedBy(arena))!
                    ..releasedBy(arena))
                  .getNumber(),
              0,
            );
          });
        });
        test('StringValuedMap', () {
          using((arena) {
            final map = StringValuedMap(K: Example.type)..releasedBy(arena);
            final example = Example()..releasedBy(arena);
            map.put(example, 'Hello'.toJString()..releasedBy(arena));
            expect(
              map.get(example)!.toDartString(releaseOriginal: true),
              'Hello',
            );
          });
        });
        test('StringMap', () {
          using((arena) {
            final map = StringMap()..releasedBy(arena);
            map.put(
              'hello'.toJString()..releasedBy(arena),
              'world'.toJString()..releasedBy(arena),
            );
            expect(
              map
                  .get('hello'.toJString()..releasedBy(arena))!
                  .toDartString(releaseOriginal: true),
              'world',
            );
          });
        });
      });
      test('superclass count', () {
        expect(JObject.type.superCount, 0);
        expect(MyMap.type(JObject.type, JObject.type).superCount, 1);
        expect(StringKeyedMap.type(JObject.type).superCount, 2);
        expect(StringValuedMap.type(JObject.type).superCount, 2);
        expect(StringMap.type.superCount, 3);
      });
      test('nested generics', () {
        using((arena) {
          final grandParent = GrandParent(
            T: JString.type,
            '!'.toJString()..releasedBy(arena),
          )..releasedBy(arena);
          expect(grandParent.value!.toDartString(releaseOriginal: true), '!');

          final strStaticParent = GrandParent.stringStaticParent()!
            ..releasedBy(arena);
          expect(
            strStaticParent.value!.toDartString(releaseOriginal: true),
            'Hello',
          );

          final exampleStaticParent = GrandParent.varStaticParent(
            S: Example.type,
            Example()..releasedBy(arena),
          )!
            ..releasedBy(arena);
          expect(
            (exampleStaticParent.value!..releasedBy(arena)).getNumber(),
            0,
          );

          final strParent = grandParent.stringParent()!..releasedBy(arena);
          expect(
            strParent.parentValue!
                .as(JString.type, releaseOriginal: true)
                .toDartString(releaseOriginal: true),
            '!',
          );
          expect(strParent.value!.toDartString(releaseOriginal: true), 'Hello');

          final exampleParent = grandParent.varParent(
            S: Example.type,
            Example()..releasedBy(arena),
          )!
            ..releasedBy(arena);
          expect(
            exampleParent.parentValue!
                .as(JString.type, releaseOriginal: true)
                .toDartString(releaseOriginal: true),
            '!',
          );
          expect((exampleParent.value!..releasedBy(arena)).getNumber(), 0);
          // TODO(#139): test constructing Child, currently does not work due
          // to a problem with C-bindings.
        });
      });
    });
    test('Constructing non-static nested classes', () {
      using((arena) {
        final grandParent = GrandParent(1.toJInteger(), T: JInteger.type)
          ..releasedBy(arena);
        final parent = GrandParent$Parent(
          grandParent,
          2.toJInteger(),
          S: JInteger.type,
        )..releasedBy(arena);
        final child = GrandParent$Parent$Child(
          parent,
          3.toJInteger(),
          U: JInteger.type,
        )..releasedBy(arena);
        expect(grandParent.value!.intValue(releaseOriginal: true), 1);
        expect(parent.parentValue!.intValue(releaseOriginal: true), 1);
        expect(parent.value!.intValue(releaseOriginal: true), 2);
        expect(child.grandParentValue!.intValue(releaseOriginal: true), 1);
        expect(child.parentValue!.intValue(releaseOriginal: true), 2);
        expect(child.value!.intValue(releaseOriginal: true), 3);
      });
    });

    group('Generic type inference', () {
      test('MyStack.of1', () {
        using((arena) {
          final emptyStack = MyStack(T: JString.type)..releasedBy(arena);
          expect(emptyStack.size(), 0);
          final stack = MyStack.of$1(
            'Hello'.toJString()..releasedBy(arena),
            T: JString.type,
          )!
            ..releasedBy(arena);
          expect(stack, isA<MyStack<JString?>>());
          expect(stack.$type, isA<$MyStack$Type<JString?>>());
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'Hello');
        });
      });
      test('MyStack.of 2 strings', () {
        using((arena) {
          final stack = MyStack.of$2(
            'Hello'.toJString()..releasedBy(arena),
            'World'.toJString()..releasedBy(arena),
            T: JString.type,
          )!
            ..releasedBy(arena);
          expect(stack, isA<MyStack<JString?>>());
          expect(stack.$type, isA<$MyStack$Type<JString?>>());
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'World');
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'Hello');
        });
      });
      test('MyStack.of a string and an array', () {
        using((arena) {
          final array = JArray.filled(1, 'World'.toJString()..releasedBy(arena))
            ..releasedBy(arena);
          final stack = MyStack.of$2(
            T: JObject.type,
            'Hello'.toJString()..releasedBy(arena),
            array,
          )!
            ..releasedBy(arena);
          expect(stack, isA<MyStack<JObject?>>());
          expect(stack.$type, isA<$MyStack$Type<JObject?>>());
          expect(
            stack
                .pop()!
                .as(JArray.type(JString.type), releaseOriginal: true)[0]
                .toDartString(releaseOriginal: true),
            'World',
          );
          expect(
            stack
                .pop()!
                .as(JString.type, releaseOriginal: true)
                .toDartString(releaseOriginal: true),
            'Hello',
          );
        });
      });
      test('MyStack.from array of string', () {
        using((arena) {
          final array = JArray.filled(1, 'Hello'.toJString()..releasedBy(arena))
            ..releasedBy(arena);
          final stack = MyStack.fromArray(T: JString.type, array)!
            ..releasedBy(arena);
          expect(stack, isA<MyStack<JString?>>());
          expect(stack.$type, isA<$MyStack$Type<JString?>>());
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'Hello');
        });
      });
      test('MyStack.fromArrayOfArrayOfGrandParents', () {
        using((arena) {
          final firstDimention = JArray.filled(
            1,
            GrandParent(T: JString.type, 'Hello'.toJString()..releasedBy(arena))
              ..releasedBy(arena),
          )..releasedBy(arena);
          final twoDimentionalArray = JArray.filled(1, firstDimention)
            ..releasedBy(arena);
          final stack = MyStack.fromArrayOfArrayOfGrandParents(
            S: JString.type,
            twoDimentionalArray,
          )!
            ..releasedBy(arena);
          expect(stack, isA<MyStack<JString?>>());
          expect(stack.$type, isA<$MyStack$Type<JString?>>());
          expect(stack.pop()!.toDartString(releaseOriginal: true), 'Hello');
        });
      });
    });
  });

  group('interface implementation', () {
    for (final (threading, consume) in [
      ('another thread', MyInterfaceConsumer.consumeOnAnotherThread),
      ('the same thread', MyInterfaceConsumer.consumeOnSameThread),
    ]) {
      test('MyInterface.implement on $threading', () async {
        final voidCallbackResult = Completer<JString>();
        final varCallbackResult = Completer<JInteger>();
        final manyPrimitivesResult = Completer<int>();
        // We can use this trick to access self, instead of generating a `thiz`
        // or `self` argument for each one of the callbacks.
        late final MyInterface<JInteger> myInterface;
        myInterface = MyInterface.implement(
          $MyInterface(
            voidCallback: voidCallbackResult.complete,
            stringCallback: (s) {
              return (s!.toDartString(releaseOriginal: true) * 2).toJString();
            },
            varCallback: (JInteger? t) {
              final result =
                  (t!.intValue(releaseOriginal: true) * 2).toJInteger();
              varCallbackResult.complete(result);
              return result;
            },
            manyPrimitives: (a, b, c, d) {
              if (b) {
                final result = a + c + d.toInt();
                manyPrimitivesResult.complete(result);
                return result;
              } else {
                // Call self, add to [a] when [b] is false and change b to true.
                return myInterface.manyPrimitives(a + 1, true, c, d);
              }
            },
            T: JInteger.type,
          ),
        );
        // [stringCallback] is going to be called first using [s].
        // The result of it is going to be used as the argument for
        // [voidCallback].
        // The other two methods will be called individually using the passed
        // arguments afterwards.
        consume(
          T: JInteger.type,
          myInterface,
          // For stringCallback:
          'hello'.toJString(),
          // For manyPrimitives:
          -1,
          false,
          3,
          3.14,
          // For varCallback
          7.toJInteger(),
        );
        final voidCallback = await voidCallbackResult.future;
        expect(voidCallback.toDartString(releaseOriginal: true), 'hellohello');

        final varCallback = await varCallbackResult.future;
        expect(varCallback.intValue(), 14);

        final manyPrimitives = await manyPrimitivesResult.future;
        expect(manyPrimitives, -1 + 3 + 3.14.toInt() + 1);

        // Running garbage collection does not work on Android. Skipping this
        // test on Android.
        // Currently we have one implementation of the interface.
        expect(MyInterface.$impls, hasLength(1), skip: Platform.isAndroid);
        myInterface.release();
        if (!Platform.isAndroid) {
          _runJavaGC();
          await _waitUntil(() => MyInterface.$impls.isEmpty);
          expect(MyInterface.$impls, isEmpty);
        }
      });
      test('implementing multiple interfaces', () async {
        final implementer = JImplementer();
        MyInterface.implementIn(
          implementer,
          $MyInterface(
            T: JString.type,
            voidCallback: (s) {},
            stringCallback: (s) {
              return s;
            },
            varCallback: (t) {
              return t;
            },
            manyPrimitives: (a, b, c, d) => 42,
          ),
        );
        var runnableRan = false;
        MyRunnable.implementIn(
          implementer,
          $MyRunnable(
            run: () {
              runnableRan = true;
            },
          ),
        );
        final runnable = implementer.implement(MyRunnable.type);
        runnable.run();
        expect(runnableRan, isTrue);
        final myInterface = runnable.as(
          MyInterface.type(JString.type),
          releaseOriginal: true,
        );
        expect(myInterface.manyPrimitives(1, true, 3, 4), 42);

        // Running garbage collection does not work on Android. Skipping this
        // test on Android.
        expect(MyInterface.$impls, hasLength(1), skip: Platform.isAndroid);
        expect(MyRunnable.$impls, hasLength(1), skip: Platform.isAndroid);
        myInterface.release();
        if (!Platform.isAndroid) {
          _runJavaGC();
          await _waitUntil(() => MyInterface.$impls.isEmpty);
          // Since the interface is now deleted, the cleaner must signal to Dart
          // to clean up.
          expect(MyInterface.$impls, isEmpty);
          expect(MyRunnable.$impls, isEmpty);
        }
      });
      test('Reuse implementation for multiple instances', () {
        using((arena) {
          final hexParser = StringConverter.implement(
            DartStringToIntParser(radix: 16),
          )..releasedBy(arena);
          final decimalParser = StringConverter.implement(
            DartStringToIntParser(radix: 10),
          )..releasedBy(arena);
          final fifteen = StringConverterConsumer.consumeOnSameThread(
            hexParser,
            'F'.toJString()..releasedBy(arena),
          )!;
          expect(fifteen.intValue(releaseOriginal: true), 15);
          final fortyTwo = StringConverterConsumer.consumeOnSameThread(
            decimalParser,
            '42'.toJString()..releasedBy(arena),
          )!;
          expect(fortyTwo.intValue(releaseOriginal: true), 42);
        });
      });
      for (final style in ['callback', 'implemented class']) {
        test('Listener callbacks - $style style', () async {
          final completer = Completer<void>();

          final MyRunnable runnable;
          if (style == 'callback') {
            runnable = MyRunnable.implement(
              $MyRunnable(run: completer.complete, run$async: true),
            );
          } else {
            runnable = MyRunnable.implement(AsyncRunnable(completer));
          }
          final runner = MyRunnableRunner(runnable);
          // Normally this would cause a deadlock, but as the callback is a
          // listener, it will work.
          runner.runOnAnotherThreadAndJoin();
          await completer.future;
          // Running garbage collection does not work on Android. Skipping
          // this test on Android.
          expect(MyRunnable.$impls, hasLength(1), skip: Platform.isAndroid);
          runnable.release();
          runner.release();
          if (!Platform.isAndroid) {
            _runJavaGC();
            await _waitUntil(() => MyInterface.$impls.isEmpty);
            // Since the interface is now deleted, the cleaner must signal to
            // Dart to clean up.
            expect(MyRunnable.$impls, isEmpty);
          }
        });
      }
      test('Object methods work', () async {
        final runnable = MyRunnable.implement($MyRunnable(run: () {}));
        expect(runnable == runnable, true);
        expect(runnable != runnable, false);
        expect(runnable.hashCode, runnable.hashCode);
        expect(runnable.toString(), runnable.toString());
        // Running garbage collection does not work on Android. Skipping
        // this test on Android.
        expect(MyRunnable.$impls, hasLength(1), skip: Platform.isAndroid);
        runnable.release();
        if (!Platform.isAndroid) {
          _runJavaGC();
          await _waitUntil(() => MyInterface.$impls.isEmpty);
          expect(MyRunnable.$impls, isEmpty);
        }
      });
    }
    group('Dart exceptions are handled', () {
      for (final exception in [UnimplementedError(), 'Hello!']) {
        for (final sameThread in [true, false]) {
          test(
              'on ${sameThread ? 'the same thread' : 'another thread'}'
              ' throwing $exception', () async {
            await using((arena) async {
              final runnable = MyRunnable.implement(
                $MyRunnable(
                  run: () {
                    // ignore: only_throw_errors
                    throw exception;
                  },
                ),
              )..releasedBy(arena);
              final runner = MyRunnableRunner(runnable)..releasedBy(arena);
              if (sameThread) {
                runner.runOnSameThread();
              } else {
                runner.runOnAnotherThread();
              }
              while (runner.error == null) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              expect(
                Jni.env.IsInstanceOf(
                  // ignore: invalid_use_of_internal_member
                  runner.error!.reference.pointer,
                  JClass.forName(
                    'java/lang/reflect/UndeclaredThrowableException',
                  )
                      // ignore: invalid_use_of_internal_member
                      .reference
                      .pointer,
                ),
                isTrue,
              );
              final throwableClass = runner.error!.jClass;
              final cause = throwableClass
                  .instanceMethodId('getCause', '()Ljava/lang/Throwable;')
                  .call(runner.error!, JObject.type, []);
              expect(
                Jni.env.IsInstanceOf(
                  // ignore: invalid_use_of_internal_member
                  cause.reference.pointer,
                  JClass.forName(
                    'com/github/dart_lang/jni/PortProxyBuilder\$DartException',
                  )
                      // ignore: invalid_use_of_internal_member
                      .reference
                      .pointer,
                ),
                isTrue,
              );
              expect(cause.toString(), contains(exception.toString()));
            });
            if (!Platform.isAndroid) {
              _runJavaGC();
            }
          });
        }
      }
    });

    group('throw Java exceptions', () {
      for (final (threading, consume) in [
        ('another thread', StringConverterConsumer.consumeOnAnotherThread),
        ('the same thread', StringConverterConsumer.consumeOnSameThread),
      ]) {
        test('StringConverter.implement on $threading ', () async {
          final stringConverter = StringConverter.implement(
            $StringConverter(
              parseToInt: (s) {
                final value = int.tryParse(s!.toDartString());
                if (value == null) {
                  // ignore: only_throw_errors
                  throw StringConversionException(
                    'Invalid integer expression: $s'.toJString(),
                  );
                }

                return value;
              },
            ),
          );

          // Gets the result of a Java Future.
          // TODO(#1213): remove this once we support Java futures.
          Future<$T> toDartFuture<$T extends JObject>(
            JObject future,
            // ignore: invalid_use_of_internal_member
            JObjType<$T> T,
          ) async {
            final receivePort = ReceivePort();
            await Isolate.spawn((sendPort) {
              final futureClass = JClass.forName('java/util/concurrent/Future');
              final getMethod = futureClass.instanceMethodId(
                'get',
                '()Ljava/lang/Object;',
              );
              final result = getMethod(future, T, []);
              // A workaround for `--pause-isolates-on-exit`. Otherwise getting
              // test with coverage pauses indefinitely here.
              // https://github.com/dart-lang/coverage/issues/472
              Isolate.current.kill();
              sendPort.send(result);
            }, receivePort.sendPort);
            return (await receivePort.first) as $T;
          }

          final sevenHundredBoxed =
              consume(stringConverter, '700'.toJString())!;
          final int sevenHundred;
          if (sevenHundredBoxed is JInteger) {
            sevenHundred = sevenHundredBoxed.intValue();
          } else {
            sevenHundred = (await toDartFuture(
              sevenHundredBoxed,
              JInteger.type,
            ))
                .intValue();
          }
          expect(sevenHundred, 700);

          final fooBoxed = consume(stringConverter, 'foo'.toJString())!;
          final int foo;
          if (fooBoxed is JInteger) {
            foo = fooBoxed.intValue();
          } else {
            foo = (await toDartFuture(fooBoxed, JInteger.type)).intValue();
          }
          expect(foo, -1);

          stringConverter.release();
        });
      }
    });
    test('Generic interface', () {
      using((arena) {
        final genericInterface = GenericInterface.implement(
          $GenericInterface(
            T: JString.type,
            arrayOf: (element) =>
                JArray(JString.nullableType, 1)..[0] = element!,
            firstKeyOf: (map) => map!.keys.first!.as(JString.type),
            firstValueOf: (map) => map!.values.first,
            firstOfArray: (array) => array![0]!.as(JString.type),
            firstOfGenericArray: (array) => array![0],
            genericArrayOf: (element) =>
                JArray(JObject.nullableType, 1)..[0] = element,
            mapOf: (key, value) =>
                JMap.hash(JString.type, JObject.type)..[key!] = value,
          ),
        )..releasedBy(arena);
        final stringArray = genericInterface
            .arrayOf('hello'.toJString()..releasedBy(arena))!
          ..releasedBy(arena);
        expect(stringArray, hasLength(1));
        expect(stringArray[0]!.toDartString(releaseOriginal: true), 'hello');
        expect(
          genericInterface
              .firstOfArray(stringArray)!
              .toDartString(releaseOriginal: true),
          'hello',
        );

        final intArray = genericInterface.genericArrayOf(
          U: JInteger.type,
          42.toJInteger()..releasedBy(arena),
        )!
          ..releasedBy(arena);
        expect(
          genericInterface
              .firstOfGenericArray(U: JInteger.type, intArray)!
              .intValue(releaseOriginal: true),
          42,
        );

        final jmap = genericInterface.mapOf(
          U: JInteger.type,
          'hello'.toJString()..releasedBy(arena),
          42.toJInteger()..releasedBy(arena),
        )!
          ..releasedBy(arena);
        expect(
          jmap['hello'.toJString()..releasedBy(arena)]!.intValue(
            releaseOriginal: true,
          ),
          42,
        );
        expect(
          genericInterface
              .firstKeyOf(U: JInteger.type, jmap)!
              .as(JString.type)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          genericInterface
              .firstValueOf(U: JInteger.type, jmap)!
              .intValue(releaseOriginal: true),
          42,
        );
      });
    });
  });

  group('Nullablity annotations', () {
    Annotated<JString?, JString, JString> newTestObject(Arena arena) {
      return Annotated(
        null,
        'hello'.toJString()..releasedBy(arena),
        'world'.toJString()..releasedBy(arena),
        T: JString.nullableType,
      )..releasedBy(arena);
    }

    Annotated<JString, JString, JString> newNonNullTestObject(Arena arena) {
      return Annotated(
        'hello'.toJString()..releasedBy(arena),
        'hello'.toJString()..releasedBy(arena),
        'world'.toJString()..releasedBy(arena),
        T: JString.type,
      )..releasedBy(arena);
    }

    test('Field access', () {
      using((arena) {
        final annotated = newTestObject(arena);
        expect(annotated.t, isNull);
        expect(annotated.u.toDartString(releaseOriginal: true), 'hello');
        expect(annotated.w.toDartString(releaseOriginal: true), 'world');
      });
    });

    test('Field setting', () {
      using((arena) {
        final annotated = newTestObject(arena);
        annotated.t = 'hello'.toJString()..releasedBy(arena);
        expect(
          annotated.t!
              .as(JString.type, releaseOriginal: true)
              .toDartString(releaseOriginal: true),
          'hello',
        );
      });
    });

    test('Static methods', () {
      expect(
        Annotated.staticHello().toDartString(releaseOriginal: true),
        'hello',
      );
    });

    test('Methods with no object args', () {
      using((arena) {
        final annotated = newTestObject(arena);
        expect(annotated.hello().toDartString(releaseOriginal: true), 'hello');
        expect(annotated.nullableHello(true), isNull);
        expect(
          annotated.nullableHello(false)!.toDartString(releaseOriginal: true),
          'hello',
        );
      });
    });

    test('Methods returning arrays', () {
      using((arena) {
        final annotated = newTestObject(arena);
        expect(
          (annotated.array()..releasedBy(arena))[0].toDartString(
            releaseOriginal: true,
          ),
          'hello',
        );
        expect((annotated.arrayOfNullable()..releasedBy(arena))[0], isNull);
        expect(annotated.nullableArray(true), isNull);
        expect(
          (annotated.nullableArray(false)!..releasedBy(arena))[0].toDartString(
            releaseOriginal: true,
          ),
          'hello',
        );
        expect(annotated.nullableArrayOfNullable(true), isNull);
        expect(
          (annotated.nullableArrayOfNullable(false)!..releasedBy(arena))[0],
          isNull,
        );
      });
    });

    test('Methods returning lists', () {
      using((arena) {
        final annotated = newTestObject(arena);
        expect(
          (annotated.list()..releasedBy(arena))[0].toDartString(
            releaseOriginal: true,
          ),
          'hello',
        );
        expect((annotated.listOfNullable()..releasedBy(arena))[0], isNull);
        expect(annotated.nullableList(true), isNull);
        expect(
          (annotated.nullableList(false)!..releasedBy(arena))[0].toDartString(
            releaseOriginal: true,
          ),
          'hello',
        );
        expect(annotated.nullableListOfNullable(true), isNull);
        expect(
          (annotated.nullableListOfNullable(false)!..releasedBy(arena))[0],
          isNull,
        );
      });
    });

    test('Methods with one object arg', () {
      using((arena) {
        final annotated = newTestObject(arena);
        final object = 'hello'.toJString()..releasedBy(arena);
        expect(
          annotated.echo(object).toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated.nullableEcho(object)!.toDartString(releaseOriginal: true),
          'hello',
        );
        expect(annotated.nullableEcho(null), isNull);
      });
    });

    test('Class generic methods with one object arg', () {
      using((arena) {
        final annotatedNullableT = newTestObject(arena);
        final object = 'hello'.toJString()..releasedBy(arena);
        expect(
          annotatedNullableT
              .classGenericEcho(object)! // Cannot make it non-nullable.
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotatedNullableT
              .nullableClassGenericEcho(object)!
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(annotatedNullableT.nullableClassGenericEcho(null), isNull);

        final annotatedNonNullableT = newNonNullTestObject(arena);
        expect(
          annotatedNonNullableT
              .classGenericEcho(object)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotatedNonNullableT
              .nullableClassGenericEcho(object)!
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(annotatedNonNullableT.nullableClassGenericEcho(null), isNull);
      });
    });

    test('Method generic methods with one object arg', () {
      using((arena) {
        final annotated = newTestObject(arena);
        final object = 'hello'.toJString()..releasedBy(arena);
        expect(
          annotated
              .methodGenericEcho(object, V: JString.nullableType)!
              // Cannot make it non-nullable.
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              .methodGenericEcho(object, V: JString.type)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              .methodGenericEcho2(object)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              .methodGenericEcho3(object)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              // Requires `V`.
              .nullableReturnMethodGenericEcho(object, false, V: JString.type)!
              // Cannot make it non-nullable.
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              // Requires `V`.
              .nullableReturnMethodGenericEcho(object, true, V: JString.type),
          isNull,
        );
        expect(
          annotated
              // `V` is optional.
              .nullableReturnMethodGenericEcho2(object, false)!
              // Cannot make it non-nullable.
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              // `V` is optional.
              .nullableReturnMethodGenericEcho2(object, true),
          isNull,
        );
        expect(
          annotated.nullableMethodGenericEcho(null, V: JString.nullableType),
          isNull,
        );
        expect(
          annotated
              .nullableMethodGenericEcho(object, V: JString.nullableType)!
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              .nullableMethodGenericEcho(object, V: JString.type)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated.noAnnotationMethodGenericEcho(
            null,
            V: JString.nullableType,
          ),
          isNull,
        );
        expect(
          annotated
              .noAnnotationMethodGenericEcho(object, V: JString.nullableType)!
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              // With no annotations, specifying a non-nullable type still
              // requires `!`.
              .noAnnotationMethodGenericEcho(object, V: JString.type)!
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          annotated
              .nullableArgMethodGenericEcho(object, V: JString.type)
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(
          () => annotated.nullableArgMethodGenericEcho<JString>(
            null,
            V: JString.type,
          ),
          throwsA(isA<JniException>()),
        );
        expect(
          annotated
              .nullableArgMethodGenericEcho<JString>(object, V: JString.type)
              .toDartString(releaseOriginal: true),
          'hello',
        );
      });
    });

    test('Class generic list methods', () {
      using((arena) {
        final annotated = newNonNullTestObject(arena);
        expect(
          (annotated.classGenericList()..releasedBy(arena)).first.toDartString(
                releaseOriginal: true,
              ),
          'hello',
        );
        expect(
          (annotated.classGenericListOfNullable()..releasedBy(arena)).first,
          isNull,
        );
        expect(annotated.nullableClassGenericList(true), isNull);
        expect(
          (annotated.nullableClassGenericList(false)!..releasedBy(arena))
              .first
              .toDartString(releaseOriginal: true),
          'hello',
        );
        expect(annotated.nullableClassGenericListOfNullable(true), isNull);
        expect(
          (annotated.nullableClassGenericListOfNullable(false)!
                ..releasedBy(arena))
              .first,
          isNull,
        );
      });
    });
  });

  group('Enums', () {
    test('Color', () {
      using((arena) {
        final red = Colors.red..releasedBy(arena);
        final green = Colors.green..releasedBy(arena);
        final blue = Colors.blue..releasedBy(arena);
        expect(red.code, 0xFF0000);
        expect(green.code, 0x00FF00);
        expect(blue.code, 0x0000FF);
        expect(red.toRGB()!..releasedBy(arena),
            Colors$RGB(255, 0, 0)..releasedBy(arena));
        expect(green.toRGB()!..releasedBy(arena),
            Colors$RGB(0, 255, 0)..releasedBy(arena));
        expect(blue.toRGB()!..releasedBy(arena),
            Colors$RGB(0, 0, 255)..releasedBy(arena));
      });
    });
  });

  group('$groupName (load tests)', () {
    const k4 = 4 * 1024; // This is a round number, unlike say 4000
    const k256 = 256 * 1024;
    test('Create large number of JNI references without deleting', () {
      for (var i = 0; i < k4; i++) {
        final e = Example.new$1(i);
        expect(e.getNumber(), equals(i));
      }
    });
    test('Create many JNI refs with scoped deletion', () {
      for (var i = 0; i < k256; i++) {
        using((arena) {
          final e = Example.new$1(i)..releasedBy(arena);
          expect(e.getNumber(), equals(i));
        });
      }
    });
    test('Create many JNI refs with scoped deletion, in batches', () {
      for (var i = 0; i < 256; i++) {
        using((arena) {
          for (var i = 0; i < 1024; i++) {
            final e = Example.new$1(i)..releasedBy(arena);
            expect(e.getNumber(), equals(i));
          }
        });
      }
    });
    test('Create large number of JNI refs with manual delete', () {
      for (var i = 0; i < k256; i++) {
        final e = Example.new$1(i);
        expect(e.getNumber(), equals(i));
        e.release();
      }
    });
    test('Method returning primitive type does not create references', () {
      using((arena) {
        final e = Example.new$1(64)..releasedBy(arena);
        for (var i = 0; i < k256; i++) {
          expect(e.getNumber(), equals(64));
        }
      });
    });
    test('Class references are cached', () {
      final asterisk = '*'.codeUnitAt(0);
      for (var i = 0; i < k256; i++) {
        expect(Fields.asterisk, equals(asterisk));
      }
    });
    void testPassageOfTime(int n) {
      test('Refs are not inadvertently deleted after $n seconds', () {
        final f = Fields();
        expect(f.trillion, equals(trillion));
        sleep(Duration(seconds: n));
        expect(f.trillion, equals(trillion));
      });
    }

    if (!Platform.isAndroid) {
      testPassageOfTime(1);
      testPassageOfTime(4);
    }
  });
}

final class DartStringToIntParser with $StringConverter {
  final int radix;

  DartStringToIntParser({required this.radix});

  @override
  int parseToInt(JString? s) {
    return int.parse(s!.toDartString(releaseOriginal: true), radix: radix);
  }
}

final class AsyncRunnable with $MyRunnable {
  final Completer<void> completer;

  AsyncRunnable(this.completer);

  @override
  Future<void> run() async {
    completer.complete();
  }

  @override
  bool get run$async => true;
}
