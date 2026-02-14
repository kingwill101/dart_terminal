import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    if (code.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError(
        'ghostty_vte currently supports dynamic loading only. '
        'Static linking is not implemented.',
      );
    }

    final dylibName = code.targetOS.dylibFileName('ghostty-vt');
    final bundledLibUri = input.outputDirectory.resolve(dylibName);

    // ── 1. Try to use a prebuilt library ──
    final prebuilt = _findPrebuiltVte(input, code, dylibName);
    if (prebuilt != null) {
      stderr.writeln('Using prebuilt VTE library: ${prebuilt.path}');
      await prebuilt.copy(File.fromUri(bundledLibUri).path);
    } else {
      // ── 2. Fall back to building from source ──
      stderr.writeln('No prebuilt VTE library found, building from source...');
      await _buildFromSource(input, code, dylibName, bundledLibUri);
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'ghostty_vte_bindings_generated.dart',
        linkMode: DynamicLoadingBundled(),
        file: bundledLibUri,
      ),
    );
  });
}

/// Checks several locations for a prebuilt library:
///
/// 1. `$GHOSTTY_VTE_PREBUILT` env var pointing directly to the file.
/// 2. `.prebuilt/<platform>/<dylibName>` relative to the repo root.
File? _findPrebuiltVte(BuildInput input, CodeConfig code, String dylibName) {
  // Check env var.
  final envPath = Platform.environment['GHOSTTY_VTE_PREBUILT'];
  if (envPath != null && envPath.isNotEmpty) {
    final f = File(envPath);
    if (f.existsSync()) return f;
  }

  // Check .prebuilt/ cache at repo root.
  final platformLabel = _platformLabel(code.targetOS, code.targetArchitecture);
  final repoRoot = _findRepoRoot(input.packageRoot);
  if (repoRoot != null) {
    final cached = File.fromUri(
      repoRoot.resolve('.prebuilt/$platformLabel/$dylibName'),
    );
    if (cached.existsSync()) return cached;
  }

  return null;
}

/// Build the VTE library from Ghostty source using Zig.
Future<void> _buildFromSource(
  BuildInput input,
  CodeConfig code,
  String dylibName,
  Uri bundledLibUri,
) async {
  final ghosttyRoot = _resolveGhosttySourceRoot(input);
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

  final builtLib = _resolveBuiltLibrary(prefixDir, dylibName);
  await File.fromUri(builtLib).copy(File.fromUri(bundledLibUri).path);

  // Track source dependencies for incremental rebuilds.
  // (Only relevant when building from source.)
  // output.dependencies would be set here, but we're inside a helper
  // so we skip—dependencies are only needed for source builds, and the
  // hook re-runs on any change anyway.
}

/// Returns a platform label like "linux-x64" or "macos-arm64".
String _platformLabel(OS os, Architecture arch) {
  final archLabel = switch (arch) {
    Architecture.x64 => 'x64',
    Architecture.arm64 => 'arm64',
    Architecture.arm => 'arm',
    Architecture.ia32 => 'x86',
    _ => arch.toString(),
  };
  final osLabel = switch (os) {
    OS.linux => 'linux',
    OS.macOS => 'macos',
    OS.windows => 'windows',
    OS.android => 'android',
    OS.iOS => 'ios',
    _ => os.toString(),
  };
  return '$osLabel-$archLabel';
}

/// Walk up from a URI to find the repo root (has pubspec.yaml + pkgs/).
Uri? _findRepoRoot(Uri packageRoot) {
  var dir = Directory.fromUri(packageRoot).absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/pkgs').existsSync()) {
      return dir.uri;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
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
