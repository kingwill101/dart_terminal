import 'dart:io';

Future<void> main() async {
  final packageRoot = _packageRoot();
  final ptyHeader = File.fromUri(
    packageRoot.uri.resolve('rust/bindings.h'),
  );
  if (!ptyHeader.existsSync()) {
    throw StateError('Missing header: ${ptyHeader.path}');
  }

  final configFile = File.fromUri(
    packageRoot.uri.resolve('.dart_tool/portable_pty_ffigen.yaml'),
  );
  configFile.parent.createSync(recursive: true);
  configFile.writeAsStringSync(
    _renderConfig(
      outputPath: File.fromUri(
        packageRoot.uri.resolve('lib/portable_pty_bindings_generated.dart'),
      ).path,
      headerPath: ptyHeader.path,
      clangIncludePath: _clangIncludePath(),
    ),
  );

  final result = await Process.start(
    'dart',
    <String>['run', 'ffigen', '--config', configFile.path],
    workingDirectory: packageRoot.path,
    runInShell: true,
  );
  await stdout.addStream(result.stdout);
  await stderr.addStream(result.stderr);
  final exit = await result.exitCode;
  if (exit != 0) {
    throw ProcessException(
      'dart',
      <String>['run', 'ffigen'],
      'ffigen failed',
      exit,
    );
  }
}

Directory _packageRoot() {
  return Directory.fromUri(Platform.script.resolve('../'));
}

String? _clangIncludePath() {
  final result = Process.runSync(
    'clang',
    const <String>['-print-resource-dir'],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final resource = (result.stdout as String).trim();
  if (resource.isEmpty) {
    return null;
  }
  final includeDir = Directory.fromUri(
    Directory(resource).uri.resolve('include/'),
  );
  if (!includeDir.existsSync()) {
    return null;
  }
  return includeDir.path;
}

String _renderConfig({
  required String outputPath,
  required String headerPath,
  required String? clangIncludePath,
}) {
  final lines = <String>[
    'name: PortablePtyBindings',
    'description: Bindings for libportable-pty C API.',
    "output: '${_yamlQuote(outputPath)}'",
    'headers:',
    '  entry-points:',
    "    - '${_yamlQuote(headerPath)}'",
    '  include-directives:',
    "    - '${_yamlQuote(headerPath)}'",
    if (clangIncludePath != null) ...[
      'compiler-opts:',
      "  - '-I${_yamlQuote(clangIncludePath)}'",
    ],
    'ffi-native:',
    'silence-enum-warning: true',
    'preamble: |',
    '  // ignore_for_file: always_specify_types',
    '  // ignore_for_file: camel_case_types',
    '  // ignore_for_file: non_constant_identifier_names',
    '  // ignore_for_file: unused_field',
    'comments:',
    '  style: any',
    '  length: full',
  ];
  return '${lines.join('\n')}\n';
}

String _yamlQuote(String value) {
  return value.replaceAll('\\', '/').replaceAll("'", "''");
}
