import 'dart:async';
import 'dart:io';

const int _defaultPort = 8080;
const String _defaultHost = '0.0.0.0';
int _nextClientId = 0;

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? _defaultPort : _defaultPort;
  final host = args.length > 1 ? args[1] : _defaultHost;
  final shell = Platform.isWindows ? 'cmd.exe' : '/bin/sh';

  final server = await HttpServer.bind(
    InternetAddress(host),
    port,
  );

  _log('mock PTY websocket server on ws://$host:$port/pty');
  _log('open: flutter example endpoint should be ws://localhost:$port/pty');
  _log('pid=${pid}');
  _log('waiting for websocket clients on /pty');

  await for (final request in server) {
    final requestId = ++_nextClientId;
    _log('[$requestId] request ${request.method} ${request.uri.path}');
    if (request.uri.path != '/pty') {
      _log('[$requestId] 404 for ${request.uri.path}');
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found')
        ..close();
      continue;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      _log('[$requestId] upgrade rejected: not a websocket request');
      request.response
        ..statusCode = HttpStatus.upgradeRequired
        ..write('websocket upgrade required')
        ..close();
      continue;
    }

    final command = request.uri.queryParameters['command'] ??
        request.uri.queryParameters['cmd'];

    final socket = await WebSocketTransformer.upgrade(request);
    _log('[$requestId] websocket upgraded on /pty');
    unawaited(_handleClient(socket, shell, requestId, commandLine: command));
  }
}

Future<void> _handleClient(
  WebSocket socket,
  String shell,
  int requestId, {
  String? commandLine,
}) async {
  _log('[$requestId] client connected');
  final targetCommand = commandLine?.trim();
  if (targetCommand != null && targetCommand.isNotEmpty) {
    _log('[$requestId] starting command from server endpoint: $targetCommand');
  } else {
    _log('[$requestId] starting interactive shell: $shell');
  }

  late Process process;
  StreamSubscription<List<int>>? stdoutSubscription;
  StreamSubscription<List<int>>? stderrSubscription;
  StreamSubscription<dynamic>? socketSubscription;

  try {
    process = await _spawnProcess(shell, targetCommand);
  } on Exception catch (error) {
    _log('[$requestId] failed to start shell process: $error');
    socket.add('failed to start shell process: $error');
    await socket.close();
    return;
  }
  _log('[$requestId] shell pid=${process.pid}');

  final closeResources = () async {
    _log('[$requestId] closing resources');
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    await socketSubscription?.cancel();
    if (socket.closeCode == null) {
      try {
        await socket.close();
      } catch (_) {}
    }
    process.kill();
  };

  stdoutSubscription = process.stdout.listen(
    (data) {
      if (socket.readyState == WebSocket.open) {
        socket.add(data);
        _log('[$requestId] stdout -> ${data.length} bytes');
      }
    },
    onDone: () {
      _log('[$requestId] stdout closed');
      socket.add('[remote stdout closed]');
    },
    onError: (error) {
      _log('[$requestId] stdout error: $error');
      socket.add('[remote stdout error] $error');
    },
  );

  stderrSubscription = process.stderr.listen(
    (data) {
      if (socket.readyState == WebSocket.open) {
        socket.add(data);
        _log('[$requestId] stderr -> ${data.length} bytes');
      }
    },
    onError: (error) {
      _log('[$requestId] stderr error: $error');
      socket.add('[remote stderr error] $error');
    },
  );

  socketSubscription = socket.listen(
    (message) {
      if (message is String) {
        _log('[$requestId] <- text message (${message.length} chars)');
      } else if (message is List<int>) {
        _log('[$requestId] <- binary message (${message.length} bytes)');
      } else if (message is List<dynamic>) {
        _log('[$requestId] <- dynamic list message (${message.length} items)');
      } else {
        _log('[$requestId] <- message of unexpected type ${message.runtimeType}');
      }

      if (message is String) {
        if (message.startsWith('env:')) {
          final preview = message.substring(0, message.length.clamp(0, 8));
          _log('[$requestId] env metadata ignored: $preview...');
          return;
        }
        if (message.contains('\u0000')) {
          _log('[$requestId] startup args message ignored');
          return;
        }
        process.stdin.write(message);
      } else if (message is List<int>) {
        process.stdin.add(message);
      } else if (message is List<dynamic>) {
        process.stdin.add(message.cast<int>());
      }
    },
    onDone: () {
      _log('[$requestId] client socket done');
      closeResources();
    },
    onError: (error) {
      _log('[$requestId] client socket error: $error');
      closeResources();
    },
  );

  unawaited(process.exitCode.whenComplete(() async {
    if (socket.readyState == WebSocket.open) {
      socket.add('[remote process ended]\n');
      await socket.close();
    }
    _log('[$requestId] process exitCode=${await process.exitCode}');
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    await socketSubscription?.cancel();
  }));
}

Future<Process> _spawnProcess(String shell, String? commandLine) async {
  final command = commandLine?.trim();
  if (command == null || command.isEmpty) {
    return Process.start(shell, const <String>[]);
  }

  if (Platform.isWindows) {
    return Process.start(shell, <String>['/c', command]);
  }

  return Process.start(shell, <String>['-lc', command]);
}

void _log(String message) {
  final now = DateTime.now();
  final stamp = now.toIso8601String();
  print('[$stamp] $message');
}
