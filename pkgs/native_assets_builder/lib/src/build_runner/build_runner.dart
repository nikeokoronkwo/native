// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_assets_cli/native_assets_cli_internal.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';

import '../dependencies_hash_file/dependencies_hash_file.dart';
import '../locking/locking.dart';
import '../model/build_result.dart';
import '../model/hook_result.dart';
import '../model/link_result.dart';
import '../package_layout/package_layout.dart';
import '../utils/run_process.dart';
import 'build_planner.dart';

typedef DependencyMetadata = Map<String, Metadata>;

typedef InputCreator = HookInputBuilder Function();

typedef BuildInputCreator = BuildInputBuilder Function();

typedef LinkInputCreator = LinkInputBuilder Function();

typedef _HookValidator =
    Future<ValidationErrors> Function(HookInput input, HookOutput output);

/// The programmatic API to be used by Dart launchers to invoke native builds.
///
/// These methods are invoked by launchers such as dartdev (for `dart run`)
/// and flutter_tools (for `flutter run` and `flutter build`).
///
/// The native assets build runner does not support reentrancy for identical
/// [BuildInput] and [LinkInput]! For more info see:
/// https://github.com/dart-lang/native/issues/1319
class NativeAssetsBuildRunner {
  final FileSystem _fileSystem;
  final Logger logger;
  final Uri dartExecutable;
  final Duration singleHookTimeout;
  final Map<String, String> hookEnvironment;
  final UserDefines? userDefines;
  final PackageLayout packageLayout;

  NativeAssetsBuildRunner({
    required this.logger,
    required this.dartExecutable,
    required FileSystem fileSystem,
    required this.packageLayout,
    Duration? singleHookTimeout,
    Map<String, String>? hookEnvironment,
    this.userDefines,
  }) : _fileSystem = fileSystem,
       singleHookTimeout = singleHookTimeout ?? const Duration(minutes: 5),
       hookEnvironment =
           hookEnvironment ??
           filteredEnvironment(hookEnvironmentVariablesFilter);

  /// Checks whether any hooks need to be run.
  ///
  /// This method is invoked by launchers such as dartdev (for `dart run`) and
  /// flutter_tools (for `flutter run` and `flutter build`).
  Future<List<String>> packagesWithBuildHooks() async {
    final planner = await _planner;
    final packagesWithHook = await planner.packagesWithHook(Hook.build);
    return packagesWithHook.map((e) => e.name).toList();
  }

  Future<HookResult?> _checkUserDefines(
    LoadedUserDefines? loadedUserDefines,
  ) async {
    if (loadedUserDefines?.pubspecErrors.isNotEmpty ?? false) {
      logger.severe('pubspec.yaml contains errors');
      for (final error in loadedUserDefines!.pubspecErrors) {
        logger.severe(error);
      }
      return null;
    }
    return HookResult(
      dependencies: switch (userDefines?.workspacePubspec) {
        null => [],
        final pubspec => [pubspec],
      },
    );
  }

  /// This method is invoked by launchers such as dartdev (for `dart run`) and
  /// flutter_tools (for `flutter run` and `flutter build`).
  ///
  /// The native assets build runner does not support reentrancy for identical
  /// [BuildInput] and [LinkInput]! For more info see:
  /// https://github.com/dart-lang/native/issues/1319
  ///
  /// The base protocol can be extended with [extensions]. See
  /// [ProtocolExtension] for more documentation.
  Future<BuildResult?> build({
    required List<ProtocolExtension> extensions,
    required bool linkingEnabled,
  }) async {
    final loadedUserDefines = await _loadedUserDefines;
    final hookResultUserDefines = await _checkUserDefines(loadedUserDefines);
    if (hookResultUserDefines == null) {
      return null;
    }
    var hookResult = hookResultUserDefines;

    final (buildPlan, packageGraph) = await _makePlan(
      hook: Hook.build,
      buildResult: null,
    );
    if (buildPlan == null) return null;

    /// Key is packageName.
    final globalMetadata = <String, Metadata>{};

    /// Key is packageName.
    final globalAssetsForBuild = <String, List<EncodedAsset>>{};
    for (final package in buildPlan) {
      final metadata =
          _metadataForPackage(
            packageGraph: packageGraph!,
            packageName: package.name,
            targetMetadata: globalMetadata,
          ) ??
          {};
      final assetsForBuild = _assetsForBuildForPackage(
        packageGraph: packageGraph,
        packageName: package.name,
        globalAssetsForBuild: globalAssetsForBuild,
      );

      final inputBuilder = BuildInputBuilder();

      for (final e in extensions) {
        e.setupBuildInput(inputBuilder);
      }
      inputBuilder.config.setupBuild(linkingEnabled: linkingEnabled);
      inputBuilder.setupBuildInput(metadata: metadata, assets: assetsForBuild);

      final (buildDirUri, outDirUri, outDirSharedUri) = await _setupDirectories(
        Hook.build,
        inputBuilder,
        package,
      );

      inputBuilder.setupShared(
        packageName: package.name,
        packageRoot: packageLayout.packageRoot(package.name),
        outputFile: buildDirUri.resolve('output.json'),
        outputDirectory: outDirUri,
        outputDirectoryShared: outDirSharedUri,
        userDefines: loadedUserDefines?[package.name],
      );

      final input = BuildInput(inputBuilder.json);
      final errors = [
        ...await validateBuildInput(input),
        for (final e in extensions) ...await e.validateBuildInput(input),
      ];
      if (errors.isNotEmpty) {
        return _printErrors(
          'Build input for ${package.name} contains errors',
          errors,
        );
      }

      final result = await _runHookForPackageCached(
        Hook.build,
        input,
        (input, output) async => [
          for (final e in extensions)
            ...await e.validateBuildOutput(
              input as BuildInput,
              output as BuildOutput,
            ),
        ],
        null,
        buildDirUri,
        outDirUri,
      );
      if (result == null) return null;
      final (hookOutput, hookDeps) = result;
      hookResult = hookResult.copyAdd(hookOutput, hookDeps);
      globalMetadata[package.name] = (hookOutput as BuildOutput).metadata;
      globalAssetsForBuild[package.name] =
          hookOutput.assets.encodedAssetsForBuild;
    }

    // We only perform application wide validation in the final result of
    // building all assets (i.e. in the build step if linking is not enabled or
    // in the link step if linking is enableD).
    if (linkingEnabled) return hookResult;

    final errors = [
      for (final e in extensions)
        ...await e.validateApplicationAssets(hookResult.encodedAssets),
    ];
    if (errors.isEmpty) return hookResult;

    _printErrors('Application asset verification failed', errors);
    return null;
  }

  /// This method is invoked by launchers such as dartdev (for `dart run`) and
  /// flutter_tools (for `flutter run` and `flutter build`).
  ///
  /// The native assets build runner does not support reentrancy for identical
  /// [BuildInput] and [LinkInput]! For more info see:
  /// https://github.com/dart-lang/native/issues/1319
  ///
  /// The base protocol can be extended with [extensions]. See
  /// [ProtocolExtension] for more documentation.
  Future<LinkResult?> link({
    required List<ProtocolExtension> extensions,
    Uri? resourceIdentifiers,
    required BuildResult buildResult,
  }) async {
    final loadedUserDefines = await _loadedUserDefines;
    final hookResultUserDefines = await _checkUserDefines(loadedUserDefines);
    if (hookResultUserDefines == null) {
      return null;
    }
    var linkResult = hookResultUserDefines;

    final (buildPlan, packageGraph) = await _makePlan(
      hook: Hook.link,
      buildResult: buildResult,
    );
    if (buildPlan == null) return null;

    for (final package in buildPlan) {
      final inputBuilder = LinkInputBuilder();
      for (final e in extensions) {
        e.setupLinkInput(inputBuilder);
      }

      final (buildDirUri, outDirUri, outDirSharedUri) = await _setupDirectories(
        Hook.link,
        inputBuilder,
        package,
      );

      File? resourcesFile;
      if (resourceIdentifiers != null) {
        resourcesFile = _fileSystem.file(buildDirUri.resolve('resources.json'));
        await resourcesFile.create();
        await _fileSystem.file(resourceIdentifiers).copy(resourcesFile.path);
      }

      inputBuilder.setupShared(
        packageName: package.name,
        packageRoot: packageLayout.packageRoot(package.name),
        outputFile: buildDirUri.resolve('output.json'),
        outputDirectory: outDirUri,
        outputDirectoryShared: outDirSharedUri,
        userDefines: loadedUserDefines?[package.name],
      );
      inputBuilder.setupLink(
        assets: buildResult.encodedAssetsForLinking[package.name] ?? [],
        recordedUsesFile: resourcesFile?.uri,
      );

      final input = LinkInput(inputBuilder.json);
      final errors = [
        ...await validateLinkInput(input),
        for (final e in extensions) ...await e.validateLinkInput(input),
      ];
      if (errors.isNotEmpty) {
        print(input.assets.encodedAssets);
        return _printErrors(
          'Link input for ${package.name} contains errors',
          errors,
        );
      }

      final result = await _runHookForPackageCached(
        Hook.link,
        input,
        (input, output) async => [
          for (final e in extensions)
            ...await e.validateLinkOutput(
              input as LinkInput,
              output as LinkOutput,
            ),
        ],
        resourceIdentifiers,
        buildDirUri,
        outDirUri,
      );
      if (result == null) return null;
      final (hookOutput, hookDeps) = result;
      linkResult = linkResult.copyAdd(hookOutput, hookDeps);
    }

    final errors = [
      for (final e in extensions)
        ...await e.validateApplicationAssets([
          ...buildResult.encodedAssets,
          ...linkResult.encodedAssets,
        ]),
    ];
    if (errors.isEmpty) return linkResult;

    _printErrors('Application asset verification failed', errors);
    return null;
  }

  Null _printErrors(String message, ValidationErrors errors) {
    assert(errors.isNotEmpty);
    logger.severe(message);
    for (final error in errors) {
      logger.severe('- $error');
    }
    return null;
  }

  Future<(Uri, Uri, Uri)> _setupDirectories(
    Hook hook,
    HookInputBuilder inputBuilder,
    Package package,
  ) async {
    final buildDirName = inputBuilder.computeChecksum();
    final packageName = package.name;
    final buildDirUri = packageLayout.dartToolNativeAssetsBuilder.resolve(
      '$packageName/$buildDirName/',
    );
    final outDirUri = buildDirUri.resolve('out/');
    final outDir = _fileSystem.directory(outDirUri);
    if (!await outDir.exists()) {
      // TODO(https://dartbug.com/50565): Purge old or unused folders.
      await outDir.create(recursive: true);
    }
    final outDirSharedUri = packageLayout.dartToolNativeAssetsBuilder.resolve(
      'shared/${package.name}/${hook.name}/',
    );
    final outDirShared = _fileSystem.directory(outDirSharedUri);
    if (!await outDirShared.exists()) {
      // TODO(https://dartbug.com/50565): Purge old or unused folders.
      await outDirShared.create(recursive: true);
    }
    return (buildDirUri, outDirUri, outDirSharedUri);
  }

  Future<(HookOutput, List<Uri>)?> _runHookForPackageCached(
    Hook hook,
    HookInput input,
    _HookValidator validator,
    Uri? resources,
    Uri buildDirUri,
    Uri outputDirectory,
  ) async => await runUnderDirectoriesLock(
    _fileSystem,
    [
      _fileSystem.directory(input.outputDirectoryShared).parent.uri,
      _fileSystem.directory(outputDirectory).parent.uri,
    ],
    timeout: singleHookTimeout,
    logger: logger,
    () async {
      final hookCompileResult = await _compileHookForPackageCached(
        input.packageName,
        buildDirUri,
        input.packageRoot.resolve('hook/${hook.scriptName}'),
      );
      if (hookCompileResult == null) {
        return null;
      }
      final (hookKernelFile, hookHashes) = hookCompileResult;

      final buildOutputFile = _fileSystem.file(input.outputFile);
      final buildOutputFileDeprecated = _fileSystem
      // ignore: deprecated_member_use
      .file(outputDirectory.resolve(hook.outputNameDeprecated));

      final dependenciesHashFile = buildDirUri.resolve(
        'dependencies.dependencies_hash_file.json',
      );
      final dependenciesHashes = DependenciesHashFile(
        _fileSystem,
        fileUri: dependenciesHashFile,
      );
      final lastModifiedCutoffTime = DateTime.now();
      if ((buildOutputFile.existsSync() ||
              buildOutputFileDeprecated.existsSync()) &&
          await dependenciesHashes.exists()) {
        late final HookOutput output;
        try {
          output = _readHookOutputFromUri(
            hook,
            buildOutputFile,
            buildOutputFileDeprecated,
          );
        } on FormatException catch (e) {
          logger.severe('''
Building assets for package:${input.packageName} failed.
${input.outputFile.toFilePath()} contained a format error.

Contents: ${buildOutputFile.readAsStringSync()}.
${e.message}
        ''');
          return null;
        }

        final outdatedDependency = await dependenciesHashes
            .findOutdatedDependency(hookEnvironment);
        if (outdatedDependency == null) {
          logger.info(
            'Skipping ${hook.name} for ${input.packageName}'
            ' in ${buildDirUri.toFilePath()}.'
            ' Last build on ${output.timestamp}.',
          );
          // All build flags go into [outDir]. Therefore we do not have to
          // check here whether the input is equal.
          return (output, hookHashes.fileSystemEntities);
        }
        logger.info(
          'Rerunning ${hook.name} for ${input.packageName}'
          ' in ${buildDirUri.toFilePath()}. $outdatedDependency',
        );
      }

      final result = await _runHookForPackage(
        hook,
        input,
        validator,
        resources,
        hookKernelFile,
        hookEnvironment,
        buildDirUri,
        outputDirectory,
      );
      if (result == null) {
        if (await dependenciesHashes.exists()) {
          await dependenciesHashes.delete();
        }
        return null;
      } else {
        final modifiedDuringBuild = await dependenciesHashes.hashDependencies(
          [
            ...result.dependencies,
            // Also depend on the compiled hook. Don't depend on the sources,
            // if only whitespace changes, we don't need to rerun the hook.
            hookKernelFile.uri,
          ],
          lastModifiedCutoffTime,
          hookEnvironment,
        );
        if (modifiedDuringBuild != null) {
          logger.severe('File modified during build. Build must be rerun.');
        }
      }
      return (result, hookHashes.fileSystemEntities);
    },
  );

  /// The list of environment variables used if [hookEnvironment] is not passed
  /// in.
  /// This allowlist lists environment variables needed to run mainstream
  /// compilers.
  static const hookEnvironmentVariablesFilter = {
    'ANDROID_HOME', // Needed for the NDK.
    'HOME', // Needed to find tools in default install locations.
    'PATH', // Needed to invoke native tools.
    'PROGRAMDATA', // Needed for vswhere.exe.
    'SYSTEMDRIVE', // Needed for CMake.
    'SYSTEMROOT', // Needed for process invocations on Windows.
    'TEMP', // Needed for temp dirs in Dart process.
    'TMP', // Needed for temp dirs in Dart process.
    'TMPDIR', // Needed for temp dirs in Dart process.
    'USERPROFILE', // Needed to find tools in default install locations.
    'WINDIR', // Needed for CMake.
  };

  Future<HookOutput?> _runHookForPackage(
    Hook hook,
    HookInput input,
    _HookValidator validator,
    Uri? resources,
    File hookKernelFile,
    Map<String, String> environment,
    Uri buildDirUri,
    Uri outputDirectory,
  ) async {
    final inputFile = buildDirUri.resolve('input.json');
    final inputFileContents = const JsonEncoder.withIndent(
      '  ',
    ).convert(input.json);
    logger.info('input.json contents:\n$inputFileContents');
    await _fileSystem.file(inputFile).writeAsString(inputFileContents);
    final hookOutputUri = input.outputFile;
    final hookOutputFile = _fileSystem.file(hookOutputUri);
    if (await hookOutputFile.exists()) {
      // Ensure we'll never read outdated build results.
      await hookOutputFile.delete();
    }
    final hookOutputUriDeprecated =
    // ignore: deprecated_member_use
    outputDirectory.resolve(hook.outputNameDeprecated);
    final hookOutputFileDeprecated = _fileSystem.file(hookOutputUriDeprecated);
    if (await hookOutputFileDeprecated.exists()) {
      // Ensure we'll never read outdated build results.
      await hookOutputFileDeprecated.delete();
    }

    final arguments = [
      '--packages=${packageLayout.packageConfigUri.toFilePath()}',
      hookKernelFile.path,
      '--config=${inputFile.toFilePath()}',
      if (resources != null) resources.toFilePath(),
    ];
    final wrappedLogger = await _createFileStreamingLogger(buildDirUri);
    final workingDirectory = input.packageRoot;
    final result = await runProcess(
      filesystem: _fileSystem,
      workingDirectory: workingDirectory,
      executable: dartExecutable,
      arguments: arguments,
      logger: wrappedLogger,
      includeParentEnvironment: false,
      environment: environment,
    );

    var deleteOutputIfExists = false;
    try {
      if (result.exitCode != 0) {
        final printWorkingDir =
            workingDirectory != _fileSystem.currentDirectory.uri;
        final commandString = [
          if (printWorkingDir) '(cd ${workingDirectory.toFilePath()};',
          dartExecutable.toFilePath(),
          ...arguments.map((a) => a.contains(' ') ? "'$a'" : a),
          if (printWorkingDir) ')',
        ].join(' ');
        logger.severe('''
  Building assets for package:${input.packageName} failed.
  ${hook.scriptName} returned with exit code: ${result.exitCode}.
  To reproduce run:
  $commandString
  stderr:
  ${result.stderr}
  stdout:
  ${result.stdout}
          ''');
        deleteOutputIfExists = true;
        return null;
      }

      final output = _readHookOutputFromUri(
        hook,
        hookOutputFile,
        hookOutputFileDeprecated,
      );
      final errors = await _validate(input, output, validator);
      if (errors.isNotEmpty) {
        _printErrors(
          '$hook hook of package:${input.packageName} has invalid output',
          errors,
        );
        deleteOutputIfExists = true;
        return null;
      }
      return output;
    } on FormatException catch (e) {
      logger.severe('''
Building assets for package:${input.packageName} failed.
${input.outputFile.toFilePath()} contained a format error.

Contents: ${hookOutputFile.readAsStringSync()}.
${e.message}
        ''');
      return null;
    } finally {
      if (deleteOutputIfExists) {
        if (await hookOutputFile.exists()) {
          await hookOutputFile.delete();
        }
      }
    }
  }

  Future<Logger> _createFileStreamingLogger(Uri buildDirUri) async {
    final stdoutFile = _fileSystem.file(buildDirUri.resolve('stdout.txt'));
    await stdoutFile.writeAsString('');
    final stderrFile = _fileSystem.file(buildDirUri.resolve('stderr.txt'));
    await stderrFile.writeAsString('');
    final wrappedLogger =
        Logger.detached('')
          ..level = Level.ALL
          ..onRecord.listen((record) async {
            logger.log(record.level, record.message);
            if (record.level <= Level.INFO) {
              await stdoutFile.writeAsString(
                '${record.message}\n',
                mode: FileMode.append,
              );
            } else {
              await stderrFile.writeAsString(
                '${record.message}\n',
                mode: FileMode.append,
              );
            }
          });
    return wrappedLogger;
  }

  /// Compiles the hook to kernel and caches the kernel.
  ///
  /// If any of the Dart source files, or the package config changed after
  /// the last time the kernel file is compiled, the kernel file is
  /// recompiled. Otherwise a cached version is used.
  ///
  /// Due to some OSes only providing last-modified timestamps with second
  /// precision. The kernel compilation cache might be considered stale if
  /// the last modification and the kernel compilation happened within one
  /// second of each other. We error on the side of caution, rather recompile
  /// one time too many, then not recompiling when recompilation should have
  /// happened.
  ///
  /// It does not reuse the cached kernel for different inputs due to
  /// reentrancy requirements. For more info see:
  /// https://github.com/dart-lang/native/issues/1319
  ///
  /// TODO(https://github.com/dart-lang/native/issues/1578): Compile only once
  /// instead of per input. This requires more locking.
  Future<(File kernelFile, DependenciesHashFile cacheFile)?>
  _compileHookForPackageCached(
    String packageName,
    Uri buildDirUri,
    Uri scriptUri,
  ) async {
    // Don't invalidate cache with environment changes.
    final environmentForCaching = <String, String>{};
    final packageConfigHashable = buildDirUri.resolve(
      'package_config_hashable.json',
    );
    await _makeHashablePackageConfig(packageConfigHashable);
    final kernelFile = _fileSystem.file(buildDirUri.resolve('hook.dill'));
    final depFile = _fileSystem.file(buildDirUri.resolve('hook.dill.d'));
    final dependenciesHashFile = buildDirUri.resolve(
      'hook.dependencies_hash_file.json',
    );
    final dependenciesHashes = DependenciesHashFile(
      _fileSystem,
      fileUri: dependenciesHashFile,
    );
    final lastModifiedCutoffTime = DateTime.now();
    var mustCompile = false;
    if (!await dependenciesHashes.exists()) {
      mustCompile = true;
    } else {
      final outdatedDependency = await dependenciesHashes
          .findOutdatedDependency(environmentForCaching);
      if (outdatedDependency != null) {
        mustCompile = true;
        logger.info(
          'Recompiling ${scriptUri.toFilePath()}. $outdatedDependency',
        );
      }
    }

    if (!mustCompile) {
      return (kernelFile, dependenciesHashes);
    }

    final success = await _compileHookForPackage(
      packageName,
      scriptUri,
      kernelFile,
      depFile,
    );
    if (!success) {
      return null;
    }

    final dartSources = await _readDepFile(depFile);

    final modifiedDuringBuild = await dependenciesHashes.hashDependencies(
      [
        ...dartSources.where((e) => e != packageLayout.packageConfigUri),
        packageConfigHashable,
        // If the Dart version changed, recompile.
        dartExecutable.resolve('../version'),
      ],
      lastModifiedCutoffTime,
      environmentForCaching,
    );
    if (modifiedDuringBuild != null) {
      logger.severe('File modified during build. Build must be rerun.');
    }

    return (kernelFile, dependenciesHashes);
  }

  Future<void> _makeHashablePackageConfig(Uri uri) async {
    final contents =
        await _fileSystem.file(packageLayout.packageConfigUri).readAsString();
    final jsonData = jsonDecode(contents) as Map<String, Object?>;
    jsonData.remove('generated');
    final contentsSanitized = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonData);
    await _fileSystem.file(uri).writeAsString(contentsSanitized);
  }

  Future<bool> _compileHookForPackage(
    String packageName,
    Uri scriptUri,
    File kernelFile,
    File depFile,
  ) async {
    final compileArguments = [
      'compile',
      'kernel',
      '--packages=${packageLayout.packageConfigUri.toFilePath()}',
      '--output=${kernelFile.path}',
      '--depfile=${depFile.path}',
      scriptUri.toFilePath(),
    ];
    final workingDirectory = packageLayout.packageConfigUri.resolve('../');
    final compileResult = await runProcess(
      filesystem: _fileSystem,
      workingDirectory: workingDirectory,
      executable: dartExecutable,
      arguments: compileArguments,
      logger: logger,
      includeParentEnvironment: true,
    );
    var success = true;
    if (compileResult.exitCode != 0) {
      final printWorkingDir =
          workingDirectory != _fileSystem.currentDirectory.uri;
      final commandString = [
        if (printWorkingDir) '(cd ${workingDirectory.toFilePath()};',
        dartExecutable.toFilePath(),
        ...compileArguments.map((a) => a.contains(' ') ? "'$a'" : a),
        if (printWorkingDir) ')',
      ].join(' ');
      logger.severe('''
Building native assets for package:$packageName failed.
Compilation of hook returned with exit code: ${compileResult.exitCode}.
To reproduce run:
$commandString
stderr:
${compileResult.stderr}
stdout:
${compileResult.stdout}
        ''');
      success = false;
      if (await depFile.exists()) {
        await depFile.delete();
      }
      if (await kernelFile.exists()) {
        await kernelFile.delete();
      }
    }
    return success;
  }

  DependencyMetadata? _metadataForPackage({
    required PackageGraph packageGraph,
    required String packageName,
    DependencyMetadata? targetMetadata,
  }) {
    if (targetMetadata == null) {
      return null;
    }
    final dependencies = packageGraph.neighborsOf(packageName).toSet();
    return {
      for (final entry in targetMetadata.entries)
        if (dependencies.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Returns only the assets output as assetForBuild by the packages that are
  /// the direct dependencies of [packageName].
  Map<String, List<EncodedAsset>>? _assetsForBuildForPackage({
    required PackageGraph packageGraph,
    required String packageName,
    Map<String, List<EncodedAsset>>? globalAssetsForBuild,
  }) {
    if (globalAssetsForBuild == null) {
      return null;
    }
    final dependencies = packageGraph.neighborsOf(packageName).toSet();
    return {
      for (final entry in globalAssetsForBuild.entries)
        if (dependencies.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<ValidationErrors> _validate(
    HookInput input,
    HookOutput output,
    _HookValidator validator,
  ) async {
    final errors =
        input is BuildInput
            ? await validateBuildOutput(input, output as BuildOutput)
            : await validateLinkOutput(
              input as LinkInput,
              output as LinkOutput,
            );
    errors.addAll(await validator(input, output));

    if (input is BuildInput) {
      final planner = await _planner;
      final packagesWithLink = (await planner.packagesWithHook(
        Hook.link,
      )).map((p) => p.name);
      for (final targetPackage
          in (output as BuildOutput).assets.encodedAssetsForLinking.keys) {
        if (!packagesWithLink.contains(targetPackage)) {
          for (final asset
              in output.assets.encodedAssetsForLinking[targetPackage]!) {
            errors.add(
              'Asset "$asset" is sent to package "$targetPackage" for'
              ' linking, but that package does not have a link hook.',
            );
          }
        }
      }
    }
    return errors;
  }

  late final _planner = () async {
    final planner = await NativeAssetsBuildPlanner.fromPackageConfigUri(
      packageConfigUri: packageLayout.packageConfigUri,
      dartExecutable: Uri.file(Platform.resolvedExecutable),
      logger: logger,
      packageLayout: packageLayout,
      fileSystem: _fileSystem,
    );
    return planner;
  }();

  Future<(List<Package>? plan, PackageGraph? dependencyGraph)> _makePlan({
    required Hook hook,
    // TODO(dacoharkes): How to share these two? Make them extend each other?
    BuildResult? buildResult,
  }) async {
    final List<Package> buildPlan;
    final PackageGraph? packageGraph;
    switch (hook) {
      case Hook.build:
        final planner = await _planner;
        final plan = await planner.makeBuildHookPlan();
        return (plan, planner.packageGraph);
      case Hook.link:
        // Link hooks are not run in any particular order.
        // Link hooks are skipped if no assets for linking are provided.
        buildPlan = [];
        final skipped = <String>[];
        final encodedAssetsForLinking = buildResult!.encodedAssetsForLinking;
        final planner = await _planner;
        final packagesWithHook = await planner.packagesWithHook(Hook.link);
        for (final package in packagesWithHook) {
          if (encodedAssetsForLinking[package.name]?.isNotEmpty ?? false) {
            buildPlan.add(package);
          } else {
            skipped.add(package.name);
          }
        }
        if (skipped.isNotEmpty) {
          logger.info(
            'Skipping link hooks from ${skipped.join(', ')}'
            ' due to no assets provided to link for these link hooks.',
          );
        }
        packageGraph = null;
    }
    return (buildPlan, packageGraph);
  }

  HookOutput _readHookOutputFromUri(
    Hook hook,
    File hookOutputFile,
    // TODO(dcharkes): Remove when hooks with 1.7.0 are no longer supported.
    File hookOutputFileDeprecated,
  ) {
    final file =
        hookOutputFile.existsSync() ? hookOutputFile : hookOutputFileDeprecated;
    final fileContents = file.readAsStringSync();
    logger.info('output.json contents:\n$fileContents');
    final hookOutputJson = jsonDecode(fileContents) as Map<String, Object?>;
    return hook == Hook.build
        ? BuildOutput(hookOutputJson)
        : LinkOutput(hookOutputJson);
  }

  /// Returns a list of errors for [_readHooksUserDefinesFromPubspec].
  static List<String> _validateHooksUserDefinesFromPubspec(
    Map<Object?, Object?> pubspec,
  ) {
    final hooks = pubspec['hooks'];
    if (hooks == null) return [];
    if (hooks is! Map) {
      return ["Expected 'hooks' to be a map. Found: '$hooks'"];
    }
    final userDefines = hooks['user_defines'];
    if (userDefines == null) return [];
    if (userDefines is! Map) {
      return [
        "Expected 'hooks.user_defines' to be a map. Found: '$userDefines'",
      ];
    }

    final errors = <String>[];
    for (final MapEntry(:key, :value) in userDefines.entries) {
      if (key is! String) {
        errors.add(
          "Expected 'hooks.user_defines' to be a map with string keys."
          " Found key: '$key'.",
        );
      }
      if (value is! Map) {
        errors.add(
          "Expected 'hooks.user_defines.$key' to be a map. Found: '$value'",
        );
        continue;
      }
      for (final childKey in value.keys) {
        if (childKey is! String) {
          errors.add(
            "Expected 'hooks.user_defines.$key' to be a "
            "map with string keys. Found key: '$childKey'.",
          );
        }
      }
    }
    return errors;
  }

  /// Reads the user-defines from a pubspec.yaml in the suggested location.
  ///
  /// SDKs do not have to follow this, they might support user-defines in a
  /// different way.
  ///
  /// The [pubspec] is expected to be the decoded yaml, a Map.
  ///
  /// Before invoking, check errors with [_validateHooksUserDefinesFromPubspec].
  static Map<String, Map<String, Object?>> _readHooksUserDefinesFromPubspec(
    Map<Object?, Object?> pubspec,
  ) {
    assert(_validateHooksUserDefinesFromPubspec(pubspec).isEmpty);
    final hooks = pubspec['hooks'];
    if (hooks is! Map) {
      return {};
    }
    final userDefines = hooks['user_defines'];
    if (userDefines is! Map) {
      return {};
    }
    return {
      for (final MapEntry(:key, :value) in userDefines.entries)
        if (key is String)
          key: {
            if (value is Map)
              for (final MapEntry(:key, :value) in value.entries)
                if (key is String) key: value,
          },
    };
  }

  late final Future<LoadedUserDefines?> _loadedUserDefines = () async {
    final pubspec = userDefines?.workspacePubspec;
    if (pubspec == null) {
      return null;
    }
    final contents = await _fileSystem.file(pubspec).readAsString();
    final decoded = loadYaml(contents) as Map<Object?, Object?>;
    final errors = _validateHooksUserDefinesFromPubspec(decoded);
    final defines = _readHooksUserDefinesFromPubspec(decoded);
    return LoadedUserDefines(
      pubspecErrors: errors,
      pubspecDefines: defines,
      pubspecBasePath: pubspec,
    );
  }();
}

/// The user-defines information passed from the SDK to the
/// [NativeAssetsBuildRunner].
///
/// Currently only holds [workspacePubspec]. (In the future this class will also
/// take command-line arguments and a working directory for the command-line
/// argument paths to be resolved against.)
class UserDefines {
  /// The pubspec.yaml of the pub workspace.
  ///
  /// User-defines are read from this file.
  final Uri? workspacePubspec;

  UserDefines({required this.workspacePubspec});
}

class LoadedUserDefines {
  final List<String> pubspecErrors;

  final Map<String, Map<String, Object?>> pubspecDefines;

  final Uri pubspecBasePath;

  LoadedUserDefines({
    required this.pubspecErrors,
    required this.pubspecDefines,
    required this.pubspecBasePath,
  });

  PackageUserDefines operator [](String packageName) => PackageUserDefines(
    workspacePubspec: switch (pubspecDefines[packageName]) {
      null => null,
      final defines => PackageUserDefinesSource(
        defines: defines,
        basePath: pubspecBasePath,
      ),
    },
  );
}

/// Parses depfile contents.
///
/// Format: `path/to/my.dill: path/to/my.dart, path/to/more.dart`
///
/// However, the spaces in paths are escaped with backslashes, and the
/// backslashes are escaped with backslashes:
///
/// ```dart
/// String _escapePath(String path) {
///   return path.replaceAll('\\', '\\\\').replaceAll(' ', '\\ ');
/// }
/// ```
@internal
List<String> parseDepFileInputs(String contents) {
  final output = contents.substring(0, contents.indexOf(': '));
  contents = contents.substring(output.length + ': '.length).trim();
  final pathsEscaped = _splitOnNonEscapedSpaces(contents);
  return pathsEscaped.map(_unescapeDepsPath).toList();
}

String _unescapeDepsPath(String path) =>
    path.replaceAll(r'\ ', ' ').replaceAll(r'\\', r'\');

List<String> _splitOnNonEscapedSpaces(String contents) {
  var index = 0;
  final result = <String>[];
  while (index < contents.length) {
    final start = index;
    while (index < contents.length) {
      final u = contents.codeUnitAt(index);
      if (u == ' '.codeUnitAt(0)) {
        break;
      }
      if (u == r'\'.codeUnitAt(0)) {
        index++;
        if (index == contents.length) {
          throw const FormatException('malformed, ending with backslash');
        }
        final v = contents.codeUnitAt(index);
        assert(v == ' '.codeUnitAt(0) || v == r'\'.codeUnitAt(0));
      }
      index++;
    }
    result.add(contents.substring(start, index));
    index++;
  }
  return result;
}

Future<List<Uri>> _readDepFile(File depFile) async {
  final depFileContents = await depFile.readAsString();
  final dartSources = parseDepFileInputs(depFileContents);
  return dartSources.map(Uri.file).toList();
}

@internal
Map<String, String> filteredEnvironment(Set<String> allowList) => {
  for (final entry in Platform.environment.entries)
    if (allowList.contains(entry.key.toUpperCase())) entry.key: entry.value,
};
