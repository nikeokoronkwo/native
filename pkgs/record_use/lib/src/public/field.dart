// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:equatable/equatable.dart';

class Field extends Equatable {
  final String className;
  final String name;
  final Object? value;

  Field({
    required this.className,
    required this.name,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'className': className,
      'name': name,
      'value': value,
    };
  }

  factory Field.fromJson(Map<String, dynamic> map) {
    return Field(
      className: map['className'] as String,
      name: map['name'] as String,
      value: map['value'],
    );
  }

  @override
  List<Object?> get props => [className, name, value];
}