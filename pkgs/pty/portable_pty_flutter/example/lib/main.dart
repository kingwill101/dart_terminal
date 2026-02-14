import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:portable_pty_flutter/portable_pty_flutter.dart';

void main() {
  runApp(const PortablePtyApp());
}

class PortablePtyApp extends StatefulWidget {
  const PortablePtyApp({super.key});

  @override
  State<PortablePtyApp> createState() => _PortablePtyAppState();
}

enum _RemoteTransportMode { webSocket, webTransport }

class _PortablePtyAppState extends State<PortablePtyApp> {
  static const String _defaultWebSocketEndpoint = 'ws://localhost:8080/pty';
  static const String _defaultWebTransportEndpoint =
      'https://localhost:8080/pty';

  late PortablePtyController _controller;
  Timer? _outputTicker;
  _RemoteTransportMode _transportMode = _RemoteTransportMode.webSocket;
  final _command = TextEditingController(text: '/bin/sh');
  final _endpoint = TextEditingController(text: _defaultWebTransportEndpoint);
  final _input = TextEditingController(text: 'echo portable_pty_flutter');

  @override
  void initState() {
    super.initState();
    _endpoint.text = _transportMode == _RemoteTransportMode.webSocket
        ? _defaultWebSocketEndpoint
        : _defaultWebTransportEndpoint;
    _controller = _createController();
    _controller.addListener(_onChange);
    _startOutputPolling();
  }

  @override
  void dispose() {
    _outputTicker?.cancel();
    _controller.removeListener(_onChange);
    _controller.dispose();
    _command.dispose();
    _endpoint.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
  }

  PortablePtyController _createController() {
    if (!kIsWeb) {
      return PortablePtyController();
    }

    return PortablePtyController(
      webSocketUrl: _transportMode == _RemoteTransportMode.webSocket
          ? _endpoint.text
          : null,
      webTransportUrl: _transportMode == _RemoteTransportMode.webTransport
          ? _endpoint.text
          : null,
    );
  }

  void _recreateController() {
    final wasRunning = _controller.isRunning;
    if (wasRunning) {
      unawaited(_controller.stop());
    }
    _controller.removeListener(_onChange);
    _controller.dispose();
    _controller = _createController();
    _controller.addListener(_onChange);
  }

  void _startOutputPolling() {
    _outputTicker?.cancel();
    _outputTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_controller.isRunning) {
        _readOutput();
      }
    });
  }

  void _onTransportModeChanged(_RemoteTransportMode mode) {
    if (_transportMode == mode) {
      return;
    }

    _transportMode = mode;
    _endpoint.text = mode == _RemoteTransportMode.webSocket
        ? _defaultWebSocketEndpoint
        : _defaultWebTransportEndpoint;

    if (kIsWeb) {
      _recreateController();
    }

    setState(() {});
  }

  Future<void> _start() async {
    if (_controller.isRunning) {
      return;
    }

    if (kIsWeb) {
      await _controller.start(
        shell: _endpoint.text,
        arguments: const <String>[],
      );
      return;
    }

    final parts = _command.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return;
    }

    final shell = parts.first;
    final arguments = parts.sublist(1);
    await _controller.start(shell: shell, arguments: arguments);
  }

  Future<void> _stop() async {
    await _controller.stop();
  }

  void _sendInput() {
    if (!_controller.isRunning) {
      return;
    }
    final wrote = _controller.write('${_input.text}\n');
    if (!wrote) {
      _controller.appendDebugOutput(
        '[failed to send input: transport is closed]\n',
      );
    }
  }

  void _readOutput() {
    final output = _controller.readOutput();
    if (output.isNotEmpty) {
      _controller.appendDebugOutput(output);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _controller.lines.join('\n');

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('portable_pty_flutter')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ElevatedButton(onPressed: _start, child: const Text('Start')),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _stop, child: const Text('Stop')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _readOutput,
                    child: const Text('Read once'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!kIsWeb) ...[
                TextField(
                  controller: _command,
                  decoration: const InputDecoration(labelText: 'Shell command'),
                ),
              ] else ...[
                Row(
                  children: [
                    const Text('Transport'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<_RemoteTransportMode>(
                        segments: const [
                          ButtonSegment(
                            value: _RemoteTransportMode.webSocket,
                            label: Text('WebSocket'),
                          ),
                          ButtonSegment(
                            value: _RemoteTransportMode.webTransport,
                            label: Text('WebTransport'),
                          ),
                        ],
                        selected: <_RemoteTransportMode>{_transportMode},
                        onSelectionChanged: (values) {
                          final value = values.isNotEmpty
                              ? values.first
                              : _transportMode;
                          _onTransportModeChanged(value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _endpoint,
                  decoration: InputDecoration(
                    labelText: _transportMode == _RemoteTransportMode.webSocket
                        ? 'WebSocket endpoint'
                        : 'WebTransport endpoint',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _input,
                decoration: const InputDecoration(labelText: 'Input to shell'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _sendInput,
                child: const Text('Write input'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SelectableText(
                  transcript.isEmpty ? 'No output yet.' : transcript,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
