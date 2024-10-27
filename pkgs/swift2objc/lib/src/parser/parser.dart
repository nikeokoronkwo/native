// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast/_core/interfaces/declaration.dart';
import '_core/parsed_symbolgraph.dart';

import '_core/utils.dart';
import 'parsers/parse_declarations.dart';
import 'parsers/parse_relations_map.dart';
import 'parsers/parse_symbols_map.dart';

/// Parses declarations from symbol graph at [symbolgraphJsonPath]
List<Declaration> parseAst(String symbolgraphJsonPath) {
  // read file into JSON
  final symbolgraphJson = readJsonFile(symbolgraphJsonPath);

  // generate parsed symbol graph from `symbols` and `relationships`
  final symbolgraph = ParsedSymbolgraph(
    parseSymbolsMap(symbolgraphJson),
    parseRelationsMap(symbolgraphJson),
  );

  // generate declarations from symbol graph
  return parseDeclarations(symbolgraph);
}
