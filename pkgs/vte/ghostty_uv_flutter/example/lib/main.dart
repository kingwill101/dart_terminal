import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ghostty_uv_flutter/ghostty_uv_flutter.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

void main() {
  runApp(const GhosttyUvStudioApp());
}

class GhosttyUvStudioApp extends StatelessWidget {
  const GhosttyUvStudioApp({super.key, this.controller, this.autoStart = true});

  final GhosttyUvTerminalController? controller;
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostty UV Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071016),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF78D2B6),
          secondary: Color(0xFF4C9E8E),
          surface: Color(0xFF0D1821),
        ),
      ),
      home: GhosttyUvStudioHome(controller: controller, autoStart: autoStart),
    );
  }
}

class GhosttyUvStudioHome extends StatefulWidget {
  const GhosttyUvStudioHome({
    super.key,
    this.controller,
    required this.autoStart,
  });

  final GhosttyUvTerminalController? controller;
  final bool autoStart;

  @override
  State<GhosttyUvStudioHome> createState() => _GhosttyUvStudioHomeState();
}

class _GhosttyUvStudioHomeState extends State<GhosttyUvStudioHome> {
  late final GhosttyUvTerminalController _controller;
  late final bool _ownsController;
  final TextEditingController _commandController = TextEditingController(
    text: 'printf "\\e[32mghostty_uv_flutter ready\\e[0m\\n"',
  );
  GhosttyTerminalShellProfile _shellProfile = GhosttyTerminalShellProfile.auto;
  bool _starting = false;
  String _launchLabel = 'not started';
  String _launchCommand = '(not started)';
  Map<String, String> _launchEnvironment = const <String, String>{};

  GhosttyTerminalShellLaunch? get _controllerLaunch =>
      _controller.activeShellLaunch;

  String get _currentLaunchLabel => _controllerLaunch?.label ?? _launchLabel;

  String get _currentLaunchCommand =>
      _controllerLaunch?.commandLine ?? _launchCommand;

  Map<String, String> get _currentLaunchEnvironment =>
      _controllerLaunch?.environment ?? _launchEnvironment;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? GhosttyUvTerminalController();
    _ownsController = widget.controller == null;
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restartShell();
      });
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _restartShell() async {
    if (_starting) {
      return;
    }

    final launch = _resolveShell(_shellProfile);
    if (launch == null) {
      setState(() {
        _launchLabel = 'no shell available';
        _launchCommand = '(not started)';
        _launchEnvironment = const <String, String>{};
      });
      return;
    }

    setState(() {
      _starting = true;
      _launchLabel = launch.label;
    });

    try {
      await _controller.restartLaunch(launch);
      if (mounted) {
        setState(() {
          _launchLabel = launch.label;
          _launchCommand = launch.commandLine;
          _launchEnvironment = launch.environment ?? const <String, String>{};
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  Future<void> _stopShell() async {
    await _controller.stop();
    if (mounted) {
      setState(() {
        _launchLabel = 'stopped';
        _launchCommand = '(stopped)';
      });
    }
  }

  Future<void> _copyShellEnvironment() async {
    final text = _formatEnvironment(_currentLaunchEnvironment);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied shell environment.')));
  }

  void _sendCommand() {
    final text = _commandController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.write('$text\n');
  }

  void _injectDemo() {
    _controller.feedOutput(
      'UV renderer demo\n'
              '\u001B[38;5;81m256-color cyan\u001B[0m\n'
              '\u001B[1;35mbold magenta\u001B[0m\n'
              '\u001B]8;;https://ghostty.org\u0007ghostty link\u001B]8;;\u0007\n'
              'emoji 🙂 width check\n'
          .codeUnits,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF071016), Color(0xFF0B1821)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight < 760 || constraints.maxWidth < 1100;
              final terminal = _TerminalCard(controller: _controller);
              final inspector = ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return _Inspector(
                    controller: _controller,
                    compact: compact,
                    shellProfile: _shellProfile,
                    launchLabel: _currentLaunchLabel,
                    launchCommand: _currentLaunchCommand,
                    launchEnvironment: _currentLaunchEnvironment,
                    onCopyEnvironment: _copyShellEnvironment,
                  );
                },
              );

              return Padding(
                padding: const EdgeInsets.all(20),
                child: compact
                    ? SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _Header(
                              shellProfile: _shellProfile,
                              launchLabel: _currentLaunchLabel,
                              controller: _controller,
                              starting: _starting,
                              onShellProfileChanged: (profile) {
                                setState(() {
                                  _shellProfile = profile;
                                });
                                _restartShell();
                              },
                              onRestart: _restartShell,
                              onStop: _stopShell,
                            ),
                            const SizedBox(height: 16),
                            _Toolbar(
                              commandController: _commandController,
                              onSend: _sendCommand,
                              onInjectDemo: _injectDemo,
                              onClear: _controller.clear,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: math
                                  .max(
                                    280,
                                    math.min(420, constraints.maxHeight * 0.55),
                                  )
                                  .toDouble(),
                              child: terminal,
                            ),
                            const SizedBox(height: 16),
                            inspector,
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _Header(
                            shellProfile: _shellProfile,
                            launchLabel: _currentLaunchLabel,
                            controller: _controller,
                            starting: _starting,
                            onShellProfileChanged: (profile) {
                              setState(() {
                                _shellProfile = profile;
                              });
                              _restartShell();
                            },
                            onRestart: _restartShell,
                            onStop: _stopShell,
                          ),
                          const SizedBox(height: 16),
                          _Toolbar(
                            commandController: _commandController,
                            onSend: _sendCommand,
                            onInjectDemo: _injectDemo,
                            onClear: _controller.clear,
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: terminal),
                          const SizedBox(height: 16),
                          inspector,
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.controller});

  final GhosttyUvTerminalController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1118),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A2A35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GhosttyUvTerminalView(
          controller: controller,
          autofocus: true,
          fontFamily: Platform.isMacOS ? 'Menlo' : 'monospace',
          cellWidthScale: 1,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.shellProfile,
    required this.launchLabel,
    required this.controller,
    required this.starting,
    required this.onShellProfileChanged,
    required this.onRestart,
    required this.onStop,
  });

  final GhosttyTerminalShellProfile shellProfile;
  final String launchLabel;
  final GhosttyUvTerminalController controller;
  final bool starting;
  final ValueChanged<GhosttyTerminalShellProfile> onShellProfileChanged;
  final VoidCallback onRestart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Ghostty UV Studio',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE6F2EE),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Separate-package prototype: shared core PTY transport, UV cell '
          'buffer, Ghostty key encoding.',
          style: TextStyle(color: Color(0xFF9EB4B1)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final profile in GhosttyTerminalShellProfile.values)
              ChoiceChip(
                label: Text(profile.label),
                selected: profile == shellProfile,
                onSelected: (_) => onShellProfileChanged(profile),
              ),
            FilledButton.tonalIcon(
              onPressed: starting ? null : onRestart,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Restart Shell'),
            ),
            OutlinedButton.icon(
              onPressed: controller.isRunning ? onStop : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop'),
            ),
            _StatusPill(
              label: controller.isRunning ? 'running' : 'idle',
              color: controller.isRunning
                  ? const Color(0xFF0E6D56)
                  : const Color(0xFF4A5964),
            ),
            _StatusPill(label: '${controller.cols} x ${controller.rows}'),
            _StatusPill(label: launchLabel),
            if (controller.exitCode case final code?)
              _StatusPill(label: 'exit $code'),
          ],
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.commandController,
    required this.onSend,
    required this.onInjectDemo,
    required this.onClear,
  });

  final TextEditingController commandController;
  final VoidCallback onSend;
  final VoidCallback onInjectDemo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: commandController,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0D1821),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            hintText: 'Shell command to write into the PTY',
            suffixIcon: IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
          onSubmitted: (_) => onSend(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send Command'),
            ),
            OutlinedButton.icon(
              onPressed: onInjectDemo,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Inject VT Demo'),
            ),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.layers_clear_rounded),
              label: const Text('Clear Screen'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.controller,
    required this.compact,
    required this.shellProfile,
    required this.launchLabel,
    required this.launchCommand,
    required this.launchEnvironment,
    required this.onCopyEnvironment,
  });

  final GhosttyUvTerminalController controller;
  final bool compact;
  final GhosttyTerminalShellProfile shellProfile;
  final String launchLabel;
  final String launchCommand;
  final Map<String, String> launchEnvironment;
  final VoidCallback onCopyEnvironment;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SnapshotCard(
            title: 'Plain Text',
            body: controller.plainText.isEmpty ? ' ' : controller.plainText,
          ),
          const SizedBox(height: 16),
          _SnapshotCard(
            title: 'Styled VT',
            body: controller.styledText.isEmpty ? ' ' : controller.styledText,
          ),
          const SizedBox(height: 16),
          _SnapshotCard(title: 'Session', body: _sessionBody()),
          const SizedBox(height: 16),
          _SnapshotCard(
            title: 'Environment',
            body: _formatEnvironment(launchEnvironment),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopyEnvironment,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Environment'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _SnapshotCard(
                title: 'Plain Text',
                body: controller.plainText.isEmpty ? ' ' : controller.plainText,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _SnapshotCard(
                title: 'Styled VT',
                body: controller.styledText.isEmpty
                    ? ' '
                    : controller.styledText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _SnapshotCard(title: 'Session', body: _sessionBody()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SnapshotCard(
                    title: 'Environment',
                    body: _formatEnvironment(launchEnvironment),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onCopyEnvironment,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy Environment'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _sessionBody() {
    return 'profile=${shellProfile.label}\n'
        'launch=$launchLabel\n'
        'command=$launchCommand\n'
        'running=${controller.isRunning}\n'
        'size=${controller.cols}x${controller.rows}\n'
        'cursor=${controller.cursorX},${controller.cursorY}\n'
        'bracketedPaste=${controller.bracketedPasteMode}\n'
        'exit=${controller.exitCode?.toString() ?? '(none)'}\n'
        'error=${controller.lastError ?? '(none)'}';
  }

  String _formatEnvironment(Map<String, String> environment) {
    if (environment.isEmpty) {
      return '(inherited or unavailable)';
    }
    final entries = environment.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1821),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1A2A35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF9AD1C0),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              body,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
              maxLines: 7,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF12222D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF243642)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

GhosttyTerminalShellLaunch? _resolveShell(GhosttyTerminalShellProfile profile) {
  final launches = ghosttyTerminalShellLaunches(
    profile: profile,
    platformEnvironment: ghosttyTerminalPlatformEnvironment(),
  );
  if (launches.isEmpty) {
    return null;
  }
  return launches.first;
}

String _formatEnvironment(Map<String, String> environment) {
  if (environment.isEmpty) {
    return '(inherited or unavailable)';
  }
  final entries = environment.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
}
