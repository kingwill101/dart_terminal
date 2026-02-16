import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart' as p;

import 'package:portable_pty/src/hook/asset_hashes.dart';

const _repo = 'kingwill101/dart_terminal';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final dylibName = code.targetOS.dylibFileName('portable_pty_rs');
    final bundledLibUri = input.outputDirectory.resolve(dylibName);

    // ── 1. Try env var ──
    final envPath = Platform.environment['PORTABLE_PTY_PREBUILT'];
    if (envPath != null && envPath.isNotEmpty) {
      final f = File(envPath);
      if (f.existsSync()) {
        stderr.writeln('Using prebuilt PTY library from env: ${f.path}');
        await f.copy(File.fromUri(bundledLibUri).path);
        _addAsset(output, input.packageName, bundledLibUri);
        return;
      }
    }

    final platformLabel = _platformLabel(
      code.targetOS,
      code.targetArchitecture,
    );

    // ── 2. Try .prebuilt/ directory (manual or setup script) ──
    final prebuilt = _findLocalPrebuilt(input, platformLabel, dylibName);
    if (prebuilt != null) {
      stderr.writeln('Using prebuilt PTY library: ${prebuilt.path}');
      await prebuilt.copy(File.fromUri(bundledLibUri).path);
      _addAsset(output, input.packageName, bundledLibUri);
      return;
    }

    // ── 3. Auto-download from GitHub releases ──
    final assetInfo = assetHashes[platformLabel];
    if (assetInfo != null) {
      stderr.writeln(
        'Downloading prebuilt PTY library for $platformLabel '
        '($releaseTag)...',
      );
      try {
        final downloaded = await _downloadPrebuilt(
          input,
          platformLabel,
          dylibName,
          assetInfo,
        );
        stderr.writeln('Using downloaded PTY library: ${downloaded.path}');
        await downloaded.copy(File.fromUri(bundledLibUri).path);
        _addAsset(output, input.packageName, bundledLibUri);
        return;
      } on Exception catch (e) {
        stderr.writeln('Download failed: $e');
        stderr.writeln('Falling back to build from source...');
      }
    }

    // ── 4. Build from source via Rust ──
    stderr.writeln('Building PTY library from source via Rust...');
    await const RustBuilder(
      assetName: 'portable_pty_bindings_generated.dart',
    ).run(input: input, output: output);
  });
}

void _addAsset(BuildOutputBuilder output, String packageName, Uri file) {
  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: 'portable_pty_bindings_generated.dart',
      linkMode: DynamicLoadingBundled(),
      file: file,
    ),
  );
}

// ── Auto-download ────────────────────────────────────────────────────

/// Downloads a prebuilt library from GitHub releases into
/// [BuildInput.outputDirectoryShared], which persists across builds.
///
/// Uses SHA256 verification and atomic writes (download to .tmp, then rename).
Future<File> _downloadPrebuilt(
  BuildInput input,
  String platformLabel,
  String dylibName,
  AssetHash assetInfo,
) async {
  // Use a stable cache directory keyed by platform + release tag.
  final cacheKey = '$platformLabel-$releaseTag';
  final cacheDir = Directory(
    input.outputDirectoryShared.resolve('pty-$cacheKey/').toFilePath(),
  );
  if (!cacheDir.existsSync()) {
    cacheDir.createSync(recursive: true);
  }

  final cachedFile = File(p.join(cacheDir.path, dylibName));

  // Check cache: if file exists and hash matches, reuse it.
  if (cachedFile.existsSync()) {
    final actualHash = await cachedFile.openRead().transform(sha256).first;
    if (actualHash.toString() == assetInfo.hash) {
      return cachedFile;
    }
    stderr.writeln('Cached file hash mismatch, re-downloading...');
  }

  // Download the tarball.
  final tarball = assetInfo.tarball;
  final url = Uri.https(
    'github.com',
    '/$_repo/releases/download/$releaseTag/$tarball',
  );

  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;

  try {
    final request = await client.getUrl(url);
    final response = await request.close();

    if (response.statusCode != 200) {
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirect = response.headers.value('location');
        if (redirect != null) {
          final redirectRequest = await client.getUrl(Uri.parse(redirect));
          final redirectResponse = await redirectRequest.close();
          if (redirectResponse.statusCode != 200) {
            throw StateError(
              'Download failed with status ${redirectResponse.statusCode} '
              'from redirect: $redirect',
            );
          }
          await _extractAndVerify(
            redirectResponse,
            cacheDir,
            cachedFile,
            dylibName,
            assetInfo.hash,
          );
          return cachedFile;
        }
      }
      throw StateError(
        'Download failed with status ${response.statusCode}: $url',
      );
    }

    await _extractAndVerify(
      response,
      cacheDir,
      cachedFile,
      dylibName,
      assetInfo.hash,
    );
  } finally {
    client.close();
  }

  return cachedFile;
}

/// Downloads the response as a tarball, extracts it, and verifies the hash
/// of the extracted library.
Future<void> _extractAndVerify(
  HttpClientResponse response,
  Directory cacheDir,
  File targetFile,
  String dylibName,
  String expectedHash,
) async {
  // Save the tarball to a temp file.
  final tarFile = File(p.join(cacheDir.path, 'download.tar.gz'));
  final sink = tarFile.openWrite();
  try {
    await response.cast<List<int>>().pipe(sink);
  } finally {
    await sink.close();
  }

  // Extract the tarball.
  final extractResult = await Process.run('tar', [
    'xzf',
    tarFile.path,
    '-C',
    cacheDir.path,
  ]);
  if (extractResult.exitCode != 0) {
    throw StateError('tar extract failed: ${extractResult.stderr}');
  }
  tarFile.deleteSync();

  // The extracted file should be the dylib. Find it.
  if (!targetFile.existsSync()) {
    final files = cacheDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).contains('portable_pty_rs'))
        .toList();
    if (files.isEmpty) {
      throw StateError(
        'Archive extracted but no portable_pty_rs library found in '
        '${cacheDir.path}',
      );
    }
    files.first.renameSync(targetFile.path);
  }

  // Verify SHA256.
  final actualHash = await targetFile.openRead().transform(sha256).first;
  if (actualHash.toString() != expectedHash) {
    targetFile.deleteSync();
    throw StateError(
      'SHA256 mismatch for $dylibName:\n'
      '  expected: $expectedHash\n'
      '  actual:   $actualHash',
    );
  }
}

// ── Local prebuilt search ────────────────────────────────────────────

File? _findLocalPrebuilt(
  BuildInput input,
  String platformLabel,
  String dylibName,
) {
  final repoRoot = _findRepoRoot(input.packageRoot);
  if (repoRoot != null) {
    final cached = File.fromUri(
      repoRoot.resolve('.prebuilt/$platformLabel/$dylibName'),
    );
    if (cached.existsSync()) return cached;
  }

  return _findPrebuiltInProjectRoots(
    input.outputDirectory,
    platformLabel,
    dylibName,
  );
}

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

File? _findPrebuiltInProjectRoots(
  Uri outputDirectory,
  String platformLabel,
  String dylibName,
) {
  var dir = Directory.fromUri(outputDirectory).absolute;
  while (true) {
    final hasPubspec = File('${dir.path}/pubspec.yaml').existsSync();
    final hasDartTool = Directory('${dir.path}/.dart_tool').existsSync();
    final hasPkgs = Directory('${dir.path}/pkgs').existsSync();

    if (hasPubspec && (hasDartTool || hasPkgs)) {
      final cached = File('${dir.path}/.prebuilt/$platformLabel/$dylibName');
      if (cached.existsSync()) return cached;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

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
