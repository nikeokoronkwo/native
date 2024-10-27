/// Comments used here are just for dev guidance
import 'dart:io';

import 'package:path/path.dart' as path;

import 'config.dart';
import 'generator/generator.dart';
import 'parser/parser.dart';
import 'transformer/transform.dart';

/// Used to generate the wrapper swift file.
Future<void> generateWrapper(Config config) async {
  final Directory tempDir;
  final bool deleteTempDirWhenDone;

  if (config.tempDir == null) {
    tempDir = Directory.systemTemp.createTempSync(defaultTempDirPrefix);
    deleteTempDirWhenDone = true;
  } else {
    tempDir = Directory.fromUri(config.tempDir!);
    deleteTempDirWhenDone = false;
  }

  // Get Input module/file
  final input = config.input;

  // Generate Symbol Graph from Input Module/File
  await _generateSymbolgraphJson(
    input.symbolgraphCommand,
    tempDir,
  );

  // Get generated symbol graph name
  final symbolgraphFileName = switch (input) {
    FilesInputConfig() => '${input.generatedModuleName}$symbolgraphFileSuffix',
    ModuleInputConfig() => '${input.module}$symbolgraphFileSuffix',
  };
  final symbolgraphJsonPath = path.join(tempDir.path, symbolgraphFileName);

  // Parse symbol graph into AST
  final declarations = parseAst(symbolgraphJsonPath);

  // Transform generated declarations 
  final transformedDeclarations = transform(declarations);

  // Generate wrapper code
  final wrapperCode = generate(transformedDeclarations, config.preamble);

  // write generated wrapper code to fs
  File.fromUri(config.outputFile).writeAsStringSync(wrapperCode);

  if (deleteTempDirWhenDone) {
    tempDir.deleteSync(recursive: true);
  }
}

Future<void> _generateSymbolgraphJson(
  Command symbolgraphCommand,
  Directory workingDirectory,
) async {
  // run gen command using exec and args from [Command]
  final result = await Process.run(
    symbolgraphCommand.executable,
    symbolgraphCommand.args,
    workingDirectory: workingDirectory.path,
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      symbolgraphCommand.executable,
      symbolgraphCommand.args,
      'Error generating symbol graph \n${result.stdout} \n${result.stderr}',
    );
  }
}
