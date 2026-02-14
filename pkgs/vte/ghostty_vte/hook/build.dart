import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final ghosttyRoot = _resolveGhosttySourceRoot(input);
    final code = input.config.code;
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError(
        'ghostty_vte currently supports dynamic loading only. '
        'Static linking is not implemented.',
      );
    }
    final target = _zigTarget(code.targetOS, code.targetArchitecture);

    final prefixDir = Directory.fromUri(
      input.outputDirectory.resolve('ghostty/$target/'),
    )..createSync(recursive: true);

    final zigArgs = <String>[
      'build',
      'lib-vt',
      '-Dtarget=$target',
      '-Doptimize=ReleaseFast',
      '-Dsimd=false',
      '--prefix',
      prefixDir.path,
      '--summary',
      'failures',
    ];

    final result = await Process.run(
      'zig',
      zigArgs,
      workingDirectory: ghosttyRoot.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to build libghostty-vt for $target.\n'
        'stdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}',
      );
    }

    final dylibName = code.targetOS.dylibFileName('ghostty-vt');
    final builtLib = _resolveBuiltLibrary(prefixDir, dylibName);
    final bundledLibUri = input.outputDirectory.resolve(dylibName);
    await File.fromUri(builtLib).copy(File.fromUri(bundledLibUri).path);

    // On macOS the Dart SDK rewrites install names after bundling via
    // install_name_tool.  Zig-built dylibs have minimal Mach-O header
    // padding so the rewrite fails with "larger updated load commands
    // do not fit".  Work around this by stripping the ad-hoc code
    // signature (which frees load-command space) so the Dart SDK's
    // rewrite has room to set the absolute-path install name.
    if (code.targetOS == OS.macOS) {
      final dylibPath = File.fromUri(bundledLibUri).path;
      await Process.run('codesign', ['--remove-signature', dylibPath]);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'ghostty_vte_bindings_generated.dart',
        linkMode: DynamicLoadingBundled(),
        file: bundledLibUri,
      ),
    );

    // Rebuild if these high-level files change.
    output.dependencies.add(ghosttyRoot.uri.resolve('build.zig'));
    output.dependencies.add(ghosttyRoot.uri.resolve('src/lib_vt.zig'));
    output.dependencies.add(ghosttyRoot.uri.resolve('include/ghostty/vt.h'));
  });
}

Directory _resolveGhosttySourceRoot(BuildInput input) {
  final envPath = Platform.environment['GHOSTTY_SRC'];
  if (envPath != null && envPath.isNotEmpty) {
    final envDir = Directory(envPath);
    if (_isGhosttyRoot(envDir)) {
      return envDir;
    }
  }

  final submoduleDir = Directory.fromUri(
    input.packageRoot.resolve('third_party/ghostty/'),
  );
  if (_envFlag('GHOSTTY_SRC_AUTO_FETCH') && !submoduleDir.existsSync()) {
    _cloneGhosttySource(submoduleDir);
  }
  if (_isGhosttyRoot(submoduleDir)) {
    return submoduleDir;
  }

  final packageRoot = Directory.fromUri(input.packageRoot);
  var current = packageRoot.absolute;
  while (true) {
    if (_isGhosttyRoot(current)) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  throw StateError(
    'Unable to locate Ghostty source root.\n'
    'Expected one of:\n'
    '- \$GHOSTTY_SRC\n'
    '- third_party/ghostty (git submodule)\n'
    '- an ancestor directory containing build.zig and include/ghostty/vt.h',
  );
}

bool _isGhosttyRoot(Directory dir) {
  final buildZig = File.fromUri(dir.uri.resolve('build.zig'));
  final vtHeader = File.fromUri(dir.uri.resolve('include/ghostty/vt.h'));
  return buildZig.existsSync() && vtHeader.existsSync();
}

bool _envFlag(String name) {
  final value = Platform.environment[name];
  if (value == null) return false;
  switch (value.toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
  }
  return false;
}

void _cloneGhosttySource(Directory targetDir) {
  final url =
      Platform.environment['GHOSTTY_SRC_URL'] ??
      'https://github.com/ghostty-org/ghostty';
  final parent = targetDir.parent;
  parent.createSync(recursive: true);

  final cloneResult = Process.runSync('git', [
    'clone',
    url,
    targetDir.path,
  ], runInShell: true);
  if (cloneResult.exitCode != 0) {
    throw StateError(
      'Failed to clone Ghostty source.\n'
      'stdout:\n${cloneResult.stdout}\n'
      'stderr:\n${cloneResult.stderr}',
    );
  }

  final ref = Platform.environment['GHOSTTY_SRC_REF'];
  if (ref != null && ref.isNotEmpty) {
    final checkoutResult = Process.runSync('git', [
      '-C',
      targetDir.path,
      'checkout',
      ref,
    ], runInShell: true);
    if (checkoutResult.exitCode != 0) {
      throw StateError(
        'Failed to checkout Ghostty ref "$ref".\n'
        'stdout:\n${checkoutResult.stdout}\n'
        'stderr:\n${checkoutResult.stderr}',
      );
    }
  }
}

String _zigTarget(OS os, Architecture arch) {
  if (os == OS.android) {
    switch (arch) {
      case Architecture.arm:
        return 'arm-linux-androideabi';
      case Architecture.arm64:
        return 'aarch64-linux-android';
      case Architecture.x64:
        return 'x86_64-linux-android';
      case Architecture.ia32:
        return 'x86-linux-android';
      default:
        break;
    }
  }

  if (os == OS.linux) {
    switch (arch) {
      case Architecture.arm:
        return 'arm-linux-gnueabihf';
      case Architecture.arm64:
        return 'aarch64-linux-gnu';
      case Architecture.x64:
        return 'x86_64-linux-gnu';
      case Architecture.ia32:
        return 'x86-linux-gnu';
      default:
        break;
    }
  }

  if (os == OS.macOS) {
    switch (arch) {
      case Architecture.arm64:
        return 'aarch64-macos';
      case Architecture.x64:
        return 'x86_64-macos';
      default:
        break;
    }
  }

  if (os == OS.windows) {
    switch (arch) {
      case Architecture.arm64:
        return 'aarch64-windows-gnu';
      case Architecture.x64:
        return 'x86_64-windows-gnu';
      case Architecture.ia32:
        return 'x86-windows-gnu';
      default:
        break;
    }
  }

  throw UnsupportedError(
    'Unsupported build target for libghostty-vt: ${os.name}/${arch.name}',
  );
}

Uri _resolveBuiltLibrary(Directory prefixDir, String dylibName) {
  final direct = File.fromUri(prefixDir.uri.resolve('lib/$dylibName'));
  if (direct.existsSync()) {
    return direct.uri;
  }

  final libDir = Directory.fromUri(prefixDir.uri.resolve('lib/'));
  if (!libDir.existsSync()) {
    throw StateError('Expected library directory: ${libDir.path}');
  }

  final matches = libDir
      .listSync()
      .whereType<FileSystemEntity>()
      .where((e) => e.path.contains('ghostty-vt'))
      .toList();
  if (matches.isEmpty) {
    throw StateError(
      'Could not find built ghostty-vt library in ${libDir.path}',
    );
  }

  // Prefer the unversioned symlink/name if it exists, otherwise first match.
  final preferred = matches.where((e) => e.path.endsWith(dylibName));
  if (preferred.isNotEmpty) {
    return preferred.first.uri;
  }
  return matches.first.uri;
}
