import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final dylibName = code.targetOS.dylibFileName('portable_pty_rs');
    final bundledLibUri = input.outputDirectory.resolve(dylibName);

    // ── 1. Try to use a prebuilt library ──
    final prebuilt = _findPrebuiltPty(input, code, dylibName);
    if (prebuilt != null) {
      stderr.writeln('Using prebuilt PTY library: ${prebuilt.path}');
      await prebuilt.copy(File.fromUri(bundledLibUri).path);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'portable_pty_bindings_generated.dart',
          linkMode: DynamicLoadingBundled(),
          file: bundledLibUri,
        ),
      );
      return;
    }

    // ── 2. Fall back to building from source via Rust ──
    stderr.writeln('No prebuilt PTY library found, building from source...');
    await const RustBuilder(
      assetName: 'portable_pty_bindings_generated.dart',
    ).run(input: input, output: output);
  });
}

/// Checks several locations for a prebuilt library:
///
/// 1. `$PORTABLE_PTY_PREBUILT` env var pointing directly to the file.
/// 2. `.prebuilt/<platform>/<dylibName>` relative to the repo root.
File? _findPrebuiltPty(BuildInput input, CodeConfig code, String dylibName) {
  // Check env var.
  final envPath = Platform.environment['PORTABLE_PTY_PREBUILT'];
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
