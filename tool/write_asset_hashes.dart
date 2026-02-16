/// Generates or verifies the `asset_hashes.dart` files for VTE and PTY.
///
/// Usage:
///   # Generate hashes from downloaded artifacts in .prebuilt/:
///   dart run tool/write_asset_hashes.dart --tag v0.0.3
///
///   # Verify existing hashes match (for CI release checks):
///   dart run tool/write_asset_hashes.dart --tag v0.0.3 --verify
///
/// This downloads all release artifacts, computes SHA256 hashes of the
/// extracted libraries, and writes/verifies the asset_hashes.dart files
/// in each package.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

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

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag':
      case '-t':
        tag = args[++i];
      case '--verify':
        verify = true;
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run tool/write_asset_hashes.dart --tag <tag> [--verify]\n'
          '\n'
          '  --tag, -t    Release tag (required)\n'
          '  --verify     Verify existing files match instead of overwriting\n',
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
    // Download and hash VTE artifacts.
    stdout.writeln('Processing VTE artifacts for $tag...');
    final vteHashes = await _downloadAndHash(tag, _vteArtifacts, tmpDir, 'vte');

    // Download and hash PTY artifacts.
    stdout.writeln('Processing PTY artifacts for $tag...');
    final ptyHashes = await _downloadAndHash(tag, _ptyArtifacts, tmpDir, 'pty');

    // Generate/verify VTE asset_hashes.dart.
    final vteContent = _generateDart(tag, vteHashes, 'vte');
    final vtePath = 'pkgs/vte/ghostty_vte/lib/src/hook/asset_hashes.dart';

    // Generate/verify PTY asset_hashes.dart.
    final ptyContent = _generateDart(tag, ptyHashes, 'pty');
    final ptyPath = 'pkgs/pty/portable_pty/lib/src/hook/asset_hashes.dart';

    if (verify) {
      var ok = true;
      ok &= _verifyFile(vtePath, vteContent);
      ok &= _verifyFile(ptyPath, ptyContent);
      if (!ok) {
        stderr.writeln(
          '\nVerification failed. Run without --verify to regenerate.',
        );
        exitCode = 1;
      } else {
        stdout.writeln('\nAll asset hashes verified successfully.');
      }
    } else {
      File(vtePath).writeAsStringSync(vteContent);
      stdout.writeln('Wrote $vtePath');
      File(ptyPath).writeAsStringSync(ptyContent);
      stdout.writeln('Wrote $ptyPath');
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
    final files = artifactDir
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.tar.gz'))
        .toList();
    if (files.isEmpty) {
      stderr.writeln('no library found');
      continue;
    }

    final libFile = files.first;
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
