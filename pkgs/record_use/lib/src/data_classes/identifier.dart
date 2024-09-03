// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:equatable/equatable.dart';

class Identifier extends Equatable {
  final String uri;
  final String? parent; // Optional since not all elements have parents
  final String name;

  Identifier({
    required this.uri,
    this.parent,
    required this.name,
  });

  factory Identifier.fromJson(Map<String, dynamic> json, List<String> uris) =>
      Identifier(
        uri: uris[json['uri'] as int],
        parent: json['parent'] as String?,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson(List<String> uris) => {
        'uri': uris.indexOf(uri),
        if (parent != null) 'parent': parent,
        'name': name,
      };

  @override
  List<Object?> get props => [uri, parent, name];
}