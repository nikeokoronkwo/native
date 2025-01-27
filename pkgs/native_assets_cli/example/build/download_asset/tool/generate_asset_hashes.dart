// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:download_asset/src/hook_helpers/download.dart';
import 'package:download_asset/src/hook_helpers/hashes.dart';
import 'package:download_asset/src/hook_helpers/targets.dart';

/// Regenerates [assetHashes].
Future<void> main(List<String> args) async {
  final assetsDir = Directory.fromUri(
      Platform.script.resolve('../.dart_tool/download_asset/'));
  await assetsDir.delete(recursive: true);
  await assetsDir.create(recursive: true);
  await Future.wait([
    for (final (targetOS, targetArchitecture, iOSSdk) in supportedTargets)
      downloadAsset(targetOS, targetArchitecture, iOSSdk, assetsDir),
  ]);
  final assetFiles = assetsDir
      .listSync(recursive: true)
      .whereType<File>()
      .toList()
    ..sort((f1, f2) => f1.path.compareTo(f2.path));
  final assetHashes = <String, String>{};
  for (final assetFile in assetFiles) {
    final fileHash = await hashAsset(assetFile);
    final target = assetFile.uri.pathSegments.lastWhere((e) => e.isNotEmpty);
    assetHashes[target] = fileHash;
  }

  await writeHashesFile(assetHashes);
}

Future<void> writeHashesFile(Map<String, String> assetHashes) async {
  final hashesFile = File.fromUri(
      Platform.script.resolve('../lib/src/hook_helpers/hashes.dart'));
  await hashesFile.create(recursive: true);
  final buffer = StringBuffer();
  buffer.write('''
// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// THIS FILE IS AUTOGENERATED. TO UPDATE, RUN
//
//    dart --enable-experiment=native-assets tool/generate_asset_hashes.dart
//

const assetHashes = <String, String>{
''');
  for (final hash in assetHashes.entries) {
    buffer.write("  '${hash.key}': '${hash.value}',\n");
  }
  buffer.write('''
};
''');
  await hashesFile.writeAsString(buffer.toString());
  await Process.run(Platform.executable, ['format', hashesFile.path]);
}
