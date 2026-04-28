/// Generates or verifies the `asset_hashes.dart` files for VTE and/or PTY.
///
/// Usage:
///   # Generate hashes for both packages:
///   dart run tool/write_asset_hashes.dart --tag ghostty_vte-v0.1.2
///
///   # Generate hashes for a single package only:
///   dart run tool/write_asset_hashes.dart --tag ghostty_vte-v0.1.2 --package vte
///   dart run tool/write_asset_hashes.dart --tag portable_pty-v0.0.4 --package pty
///
///   # Verify existing hashes match (for CI release checks):
///   dart run tool/write_asset_hashes.dart --tag ghostty_vte-v0.1.2 --verify
///
/// This downloads all release artifacts, computes SHA256 hashes of the
/// extracted libraries, and writes/verifies the asset_hashes.dart files
/// in each package.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import '../pkgs/vte/ghostty_vte/lib/src/hook/dynamic_library.dart';

const _repo = 'kingwill101/dart_terminal';

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
  'ios-arm64': 'vte-ios-arm64.tar.gz',
  'ios-sim-arm64': 'vte-ios-sim-arm64.tar.gz',
  'ios-sim-x64': 'vte-ios-sim-x64.tar.gz',
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
  String? tag;
  var verify = false;
  var package = 'all'; // vte | pty | all

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag':
      case '-t':
        tag = args[++i];
      case '--verify':
        verify = true;
      case '--package':
      case '-p':
        package = args[++i];
        if (!{'vte', 'pty', 'all'}.contains(package)) {
          stderr.writeln(
            "Error: --package must be one of: vte, pty, all (got '$package')",
          );
          exitCode = 1;
          return;
        }
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run tool/write_asset_hashes.dart --tag <tag> [--package vte|pty|all] [--verify]\n'
          '\n'
          '  --tag, -t        Release tag (required)\n'
          '  --package, -p    Which package to process: vte, pty, or all (default: all)\n'
          '  --verify         Verify existing files match instead of overwriting\n',
        );
        return;
    }
  }

  if (tag == null) {
    stderr.writeln('Error: --tag is required');
    exitCode = 1;
    return;
  }

  final tmpDir = await Directory.systemTemp.createTemp('asset_hashes_');

  try {
    if (package == 'vte' || package == 'all') {
      // Download and hash VTE artifacts.
      stdout.writeln('Processing VTE artifacts for $tag...');
      final vteHashes = await _downloadAndHash(
        tag,
        _vteArtifacts,
        tmpDir,
        'vte',
      );

      final vteContent = _generateDart(tag, vteHashes, 'vte');
      final vtePath = 'pkgs/vte/ghostty_vte/lib/src/hook/asset_hashes.dart';

      if (verify) {
        if (!_verifyFile(vtePath, vteContent)) {
          stderr.writeln(
            '\nVerification failed. Run without --verify to regenerate.',
          );
          exitCode = 1;
          return;
        } else {
          stdout.writeln('OK: $vtePath');
        }
      } else {
        File(vtePath).writeAsStringSync(vteContent);
        stdout.writeln('Wrote $vtePath');
      }
    }

    if (package == 'pty' || package == 'all') {
      // Download and hash PTY artifacts.
      stdout.writeln('Processing PTY artifacts for $tag...');
      final ptyHashes = await _downloadAndHash(
        tag,
        _ptyArtifacts,
        tmpDir,
        'pty',
      );

      final ptyContent = _generateDart(tag, ptyHashes, 'pty');
      final ptyPath = 'pkgs/pty/portable_pty/lib/src/hook/asset_hashes.dart';

      if (verify) {
        if (!_verifyFile(ptyPath, ptyContent)) {
          stderr.writeln(
            '\nVerification failed. Run without --verify to regenerate.',
          );
          exitCode = 1;
          return;
        } else {
          stdout.writeln('OK: $ptyPath');
        }
      } else {
        File(ptyPath).writeAsStringSync(ptyContent);
        stdout.writeln('Wrote $ptyPath');
      }
    }

    if (verify) {
      stdout.writeln('\nAll asset hashes verified successfully.');
    }
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}

Future<Map<String, String>> _downloadAndHash(
  String tag,
  Map<String, String> artifacts,
  Directory tmpDir,
  String packagePrefix,
) async {
  final hashes = <String, String>{};

  for (final entry in artifacts.entries) {
    final platform = entry.key;
    final tarball = entry.value;

    stdout.write('  $platform ($tarball)... ');

    final artifactDir = Directory('${tmpDir.path}/$packagePrefix-$platform')
      ..createSync(recursive: true);

    // Download using gh CLI.
    final dlResult = await Process.run('gh', [
      'release',
      'download',
      tag,
      '--repo',
      _repo,
      '--pattern',
      tarball,
      '--dir',
      artifactDir.path,
      '--clobber',
    ]);

    if (dlResult.exitCode != 0) {
      stderr.writeln('FAILED: ${dlResult.stderr}');
      continue;
    }

    // Extract.
    final tarPath = '${artifactDir.path}/$tarball';
    final extractResult = await Process.run('tar', [
      'xzf',
      tarPath,
      '-C',
      artifactDir.path,
    ]);
    if (extractResult.exitCode != 0) {
      stderr.writeln('tar failed: ${extractResult.stderr}');
      continue;
    }
    File(tarPath).deleteSync();

    // Find and hash the extracted library.
    final canonicalName = packagePrefix == 'vte'
        ? dynamicLibraryNameForPlatform(platform, 'ghostty-vt')
        : null;

    final files = artifactDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.endsWith('.tar.gz'))
        .toList();
    if (files.isEmpty) {
      stderr.writeln('no library found');
      continue;
    }

    final libFile = canonicalName == null
        ? files.first
        : switch (selectDynamicLibraryEntity(
            files,
            canonicalName: canonicalName,
          )) {
            final FileSystemEntity entity => File(entity.path),
            null => throw StateError(
              'No matching dynamic library found for $platform in ${artifactDir.path}',
            ),
          };

    if (canonicalName != null) {
      ensureDynamicLibraryFile(
        libFile,
        canonicalName: canonicalName,
        sourceDescription: tarball,
      );
    }

    final hash = (await libFile.openRead().transform(sha256).first).toString();
    hashes[platform] = hash;
    stdout.writeln('$hash');
  }

  return hashes;
}

String _generateDart(String tag, Map<String, String> hashes, String libName) {
  final description = libName == 'vte' ? 'ghostty-vt' : 'portable_pty_rs';
  final artifactMap = libName == 'vte' ? _vteArtifacts : _ptyArtifacts;

  final buffer = StringBuffer()
    ..writeln('// Hashes of prebuilt $description binaries for each platform.')
    ..writeln('// Used by the build hook to verify downloaded artifacts.')
    ..writeln('//')
    ..writeln('// Generated by tool/write_asset_hashes.dart')
    ..writeln()
    ..writeln('// dart format off')
    ..writeln()
    ..writeln(
      '/// The GitHub release tag from which prebuilt binaries are downloaded.',
    )
    ..writeln("const String releaseTag = '$tag';")
    ..writeln()
    ..writeln('/// Maps platform labels to artifact info and SHA256 hashes.')
    ..writeln('const Map<String, AssetHash> assetHashes = {');

  for (final entry in hashes.entries) {
    final platform = entry.key;
    final hash = entry.value;
    final tarball = artifactMap[platform]!;
    buffer.writeln("  '$platform': AssetHash(");
    buffer.writeln("    tarball: '$tarball',");
    buffer.writeln("    hash: '$hash',");
    buffer.writeln('  ),');
  }

  buffer
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// Describes a prebuilt artifact with its download filename and '
      'integrity hash.',
    )
    ..writeln('class AssetHash {')
    ..writeln(
      '  /// The tarball filename in the GitHub release '
      '(e.g. "$libName-linux-x64.tar.gz").',
    )
    ..writeln('  final String tarball;')
    ..writeln()
    ..writeln('  /// SHA256 hash of the extracted library file.')
    ..writeln('  final String hash;')
    ..writeln()
    ..writeln('  const AssetHash({required this.tarball, required this.hash});')
    ..writeln('}');

  return buffer.toString();
}

bool _verifyFile(String path, String expectedContent) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('MISSING: $path');
    return false;
  }
  final actual = file.readAsStringSync();
  if (actual == expectedContent) {
    stdout.writeln('OK: $path');
    return true;
  } else {
    stderr.writeln('MISMATCH: $path');
    return false;
  }
}
