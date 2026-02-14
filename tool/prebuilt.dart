/// Downloads prebuilt native libraries from GitHub Releases.
///
/// Usage:
///   dart run tool/prebuilt.dart [--tag v0.0.1] [--lib vte|pty|all]
///                               [--platform linux-x64] [--all-platforms]
///
/// Downloads are cached in `.prebuilt/` at the repo root. Build hooks
/// check this directory before compiling from source.
library;

import 'dart:io';

const _repo = 'kingwill101/dart_terminal';
const _defaultTag = 'latest';

/// Maps (library, OS, arch) → the tar.gz artifact name in the release.
const _vteArtifacts = <String, String>{
  'linux-x64': 'vte-linux-x64.tar.gz',
  'linux-arm64': 'vte-linux-arm64.tar.gz',
  'macos-arm64': 'vte-macos-arm64.tar.gz',
  'macos-x64': 'vte-macos-x64.tar.gz',
  'windows-x64': 'vte-windows-x64.tar.gz',
  'windows-arm64': 'vte-windows-arm64.tar.gz',
  'android-arm64': 'vte-android-arm64.tar.gz',
  'android-arm': 'vte-android-arm.tar.gz',
  'android-x64': 'vte-android-x64.tar.gz',
  'wasm': 'vte-wasm.tar.gz',
};

const _ptyArtifacts = <String, String>{
  'linux-x64': 'pty-linux-x64.tar.gz',
  'linux-arm64': 'pty-linux-arm64.tar.gz',
  'macos-arm64': 'pty-macos-arm64.tar.gz',
  'macos-x64': 'pty-macos-x64.tar.gz',
  'windows-x64': 'pty-windows-x64.tar.gz',
  'android-arm64': 'pty-android-arm64.tar.gz',
  'android-arm': 'pty-android-arm.tar.gz',
  'android-x64': 'pty-android-x64.tar.gz',
  'ios-arm64': 'pty-ios-arm64.tar.gz',
  'ios-sim-arm64': 'pty-ios-sim-arm64.tar.gz',
};

Future<void> main(List<String> args) async {
  var tag = _defaultTag;
  var lib = 'all';
  String? platform;
  var allPlatforms = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag':
      case '-t':
        tag = args[++i];
      case '--lib':
      case '-l':
        lib = args[++i];
      case '--platform':
      case '-p':
        platform = args[++i];
      case '--all-platforms':
        allPlatforms = true;
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run tool/prebuilt.dart [options]\n'
          '\n'
          '  --tag, -t       Release tag (default: latest)\n'
          '  --lib, -l       vte | pty | all (default: all)\n'
          '  --platform, -p  e.g. linux-x64, macos-arm64 (default: host)\n'
          '  --all-platforms Download for all platforms\n',
        );
        return;
    }
  }

  platform ??= _hostPlatform();

  // Resolve the repo root (.prebuilt/ cache directory).
  final repoRoot = _findRepoRoot(Directory.current);
  final cacheDir = Directory('${repoRoot.path}/.prebuilt')
    ..createSync(recursive: true);

  stdout.writeln('Cache directory: ${cacheDir.path}');
  stdout.writeln('Release tag:     $tag');
  stdout.writeln('');

  final artifacts = <String, String>{};
  if (lib == 'vte' || lib == 'all') {
    if (allPlatforms) {
      artifacts.addAll(_vteArtifacts);
    } else {
      // Download the specific platform + wasm.
      if (_vteArtifacts.containsKey(platform)) {
        artifacts[platform] = _vteArtifacts[platform]!;
      }
      artifacts['wasm'] = _vteArtifacts['wasm']!;
    }
  }
  if (lib == 'pty' || lib == 'all') {
    if (allPlatforms) {
      artifacts.addAll(_ptyArtifacts);
    } else if (_ptyArtifacts.containsKey(platform)) {
      artifacts[platform] = _ptyArtifacts[platform]!;
    }
  }

  if (artifacts.isEmpty) {
    stderr.writeln('No artifacts to download for platform "$platform".');
    exitCode = 1;
    return;
  }

  final resolvedTag = await _resolveTag(tag);
  stdout.writeln('Resolved tag: $resolvedTag\n');

  var failures = 0;
  for (final entry in artifacts.entries) {
    final label = entry.key;
    final filename = entry.value;
    final outDir = Directory('${cacheDir.path}/$label')
      ..createSync(recursive: true);

    stdout.write('  $filename → ${outDir.path} ... ');
    try {
      await _downloadAndExtract(resolvedTag, filename, outDir);
      stdout.writeln('✓');
    } on Exception catch (e) {
      stdout.writeln('✗');
      stderr.writeln('    $e');
      failures++;
    }
  }

  stdout.writeln('');
  if (failures > 0) {
    stderr.writeln('$failures artifact(s) failed to download.');
    exitCode = 1;
  } else {
    stdout.writeln('All artifacts downloaded successfully.');
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

String _hostPlatform() {
  final os = Platform.operatingSystem;
  // Dart's Platform doesn't expose arch directly; use uname / wmic.
  final arch = _hostArch();
  switch (os) {
    case 'linux':
      return 'linux-$arch';
    case 'macos':
      return 'macos-$arch';
    case 'windows':
      return 'windows-$arch';
    default:
      return '$os-$arch';
  }
}

String _hostArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
    return pa.contains('ARM') ? 'arm64' : 'x64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  switch (machine) {
    case 'x86_64':
    case 'amd64':
      return 'x64';
    case 'aarch64':
    case 'arm64':
      return 'arm64';
    default:
      return machine;
  }
}

Directory _findRepoRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/pkgs').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return start;
    dir = parent;
  }
}

Future<String> _resolveTag(String tag) async {
  if (tag != 'latest') return tag;

  final result = await Process.run('gh', [
    'release',
    'view',
    '--repo',
    _repo,
    '--json',
    'tagName',
    '-q',
    '.tagName',
  ]);
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to resolve latest release tag. '
      'Is `gh` CLI installed and authenticated?\n${result.stderr}',
    );
  }
  return (result.stdout as String).trim();
}

Future<void> _downloadAndExtract(
  String tag,
  String filename,
  Directory outDir,
) async {
  final url =
      'https://github.com/$_repo/releases/download/$tag/$filename';

  // Download with curl (available on all platforms).
  final tarPath = '${outDir.path}/$filename';
  final dlResult = await Process.run('curl', [
    '-fSL',
    '--retry',
    '3',
    '-o',
    tarPath,
    url,
  ]);
  if (dlResult.exitCode != 0) {
    throw Exception('curl failed for $url: ${dlResult.stderr}');
  }

  // Extract.
  final extractResult = await Process.run('tar', [
    'xzf',
    tarPath,
    '-C',
    outDir.path,
  ]);
  if (extractResult.exitCode != 0) {
    throw Exception('tar extract failed: ${extractResult.stderr}');
  }

  // Remove the tarball.
  File(tarPath).deleteSync();
}
