import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGhosttyVteWeb();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostty VT Studio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TerminalStudioPage(),
    );
  }
}

class TerminalStudioPage extends StatefulWidget {
  const TerminalStudioPage({super.key});

  @override
  State<TerminalStudioPage> createState() => _TerminalStudioPageState();
}

class _TerminalStudioPageState extends State<TerminalStudioPage> {
  final GhosttyTerminalController _terminal = GhosttyTerminalController();
  final TextEditingController _terminalController = TextEditingController(
    text: 'echo "hello from ghostty_vte"',
  );
  final TextEditingController _oscController = TextEditingController(
    text: '0;Ghostty VT Studio',
  );
  final TextEditingController _sgrController = TextEditingController(
    text: '1;31;4',
  );
  final TextEditingController _utf8Controller = TextEditingController(
    text: 'c',
  );
  final TextEditingController _codepointController = TextEditingController(
    text: '0x63',
  );

  static const List<_ModOption> _modOptions = <_ModOption>[
    _ModOption('Shift', GhosttyModsMask.shift),
    _ModOption('Ctrl', GhosttyModsMask.ctrl),
    _ModOption('Alt', GhosttyModsMask.alt),
    _ModOption('Super', GhosttyModsMask.superKey),
    _ModOption('Caps', GhosttyModsMask.capsLock),
    _ModOption('Num', GhosttyModsMask.numLock),
  ];

  static const List<_FlagOption> _kittyFlagOptions = <_FlagOption>[
    _FlagOption('Disambiguate', GhosttyKittyFlags.disambiguate),
    _FlagOption('Events', GhosttyKittyFlags.reportEvents),
    _FlagOption('Alternates', GhosttyKittyFlags.reportAlternates),
    _FlagOption('Report all', GhosttyKittyFlags.reportAll),
    _FlagOption('Associated text', GhosttyKittyFlags.reportAssociated),
  ];

  static const List<GhosttyKey> _keyOptions = <GhosttyKey>[
    GhosttyKey.GHOSTTY_KEY_C,
    GhosttyKey.GHOSTTY_KEY_V,
    GhosttyKey.GHOSTTY_KEY_ENTER,
    GhosttyKey.GHOSTTY_KEY_TAB,
    GhosttyKey.GHOSTTY_KEY_BACKSPACE,
    GhosttyKey.GHOSTTY_KEY_ESCAPE,
    GhosttyKey.GHOSTTY_KEY_ARROW_UP,
    GhosttyKey.GHOSTTY_KEY_ARROW_DOWN,
    GhosttyKey.GHOSTTY_KEY_ARROW_LEFT,
    GhosttyKey.GHOSTTY_KEY_ARROW_RIGHT,
    GhosttyKey.GHOSTTY_KEY_F1,
    GhosttyKey.GHOSTTY_KEY_F2,
    GhosttyKey.GHOSTTY_KEY_F3,
    GhosttyKey.GHOSTTY_KEY_F4,
  ];

  bool _pasteSafe = true;
  VtOscCommand? _oscCommand;
  String? _oscError;
  int _oscTerminator = 0x07;

  List<VtSgrAttributeData> _sgrAttributes = <VtSgrAttributeData>[];
  String? _sgrError;

  GhosttyKeyAction _selectedAction = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
  GhosttyKey _selectedKey = GhosttyKey.GHOSTTY_KEY_C;
  final Set<int> _mods = <int>{GhosttyModsMask.ctrl};
  final Set<int> _consumedMods = <int>{};
  bool _composing = false;
  int _kittyFlags = GhosttyKittyFlags.all;
  bool _cursorKeyApplication = false;
  bool _keypadKeyApplication = false;
  bool _ignoreKeypadWithNumLock = true;
  bool _altEscPrefix = true;
  bool _modifyOtherKeysState2 = true;
  Uint8List _encodedBytes = Uint8List(0);
  String? _keyError;

  final List<String> _activity = <String>[];

  @override
  void initState() {
    super.initState();
    _terminal.addListener(_onTerminalChanged);
    _recomputeAll(addLog: false);
  }

  @override
  void dispose() {
    _terminal.removeListener(_onTerminalChanged);
    _terminal.dispose();
    _terminalController.dispose();
    _oscController.dispose();
    _sgrController.dispose();
    _utf8Controller.dispose();
    _codepointController.dispose();
    super.dispose();
  }

  void _onTerminalChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _activity.insert(0, '$hh:$mm:$ss  $message');
    if (_activity.length > 120) {
      _activity.removeLast();
    }
  }

  Future<void> _startTerminal() async {
    try {
      await _terminal.start();
      _appendLog('Started terminal shell process.');
      setState(() {});
    } catch (error) {
      _appendLog('Failed to start terminal: $error');
      setState(() {});
    }
  }

  Future<void> _stopTerminal() async {
    await _terminal.stop();
    _appendLog('Stopped terminal shell process.');
    setState(() {});
  }

  void _sendTerminalInput() {
    final input = _terminalController.text;
    final wrote = _terminal.write('$input\n', sanitizePaste: true);
    if (wrote) {
      _appendLog('Sent command to terminal stdin.');
    } else {
      _appendLog(
        'Command not sent (terminal stopped or paste safety blocked).',
      );
    }
    setState(() {});
  }

  void _recomputeAll({bool addLog = true}) {
    _computePasteSafety();
    _parseOsc();
    _parseSgr();
    _encodeKey();
    if (addLog) {
      _appendLog(
        'Ran full evaluation across terminal, OSC, SGR, and key APIs.',
      );
    }
  }

  void _computePasteSafety() {
    _pasteSafe = GhosttyVt.isPasteSafe(_terminalController.text);
  }

  void _parseOsc() {
    final parser = VtOscParser();
    try {
      parser.addText(_oscController.text);
      _oscCommand = parser.end(terminator: _oscTerminator);
      _oscError = null;
    } catch (error) {
      _oscCommand = null;
      _oscError = error.toString();
    } finally {
      parser.close();
    }
  }

  List<int> _parseSgrParams(String raw) {
    return RegExp(
      r'\d+',
    ).allMatches(raw).map((m) => int.parse(m.group(0)!)).toList();
  }

  void _parseSgr() {
    final params = _parseSgrParams(_sgrController.text);
    if (params.isEmpty) {
      _sgrAttributes = <VtSgrAttributeData>[];
      _sgrError = 'Provide at least one integer parameter (example: 1;31;4).';
      return;
    }

    final parser = VtSgrParser();
    try {
      _sgrAttributes = parser.parseParams(params);
      _sgrError = null;
    } catch (error) {
      _sgrAttributes = <VtSgrAttributeData>[];
      _sgrError = error.toString();
    } finally {
      parser.close();
    }
  }

  int _modsToMask(Set<int> values) {
    var out = 0;
    for (final value in values) {
      out |= value;
    }
    return out;
  }

  int _parseCodepoint(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
      return int.parse(trimmed.substring(2), radix: 16);
    }
    return int.parse(trimmed);
  }

  void _encodeKey() {
    final event = VtKeyEvent();
    final encoder = VtKeyEncoder();
    try {
      event
        ..action = _selectedAction
        ..key = _selectedKey
        ..mods = _modsToMask(_mods)
        ..consumedMods = _modsToMask(_consumedMods)
        ..composing = _composing
        ..utf8Text = _utf8Controller.text
        ..unshiftedCodepoint = _parseCodepoint(_codepointController.text);

      encoder
        ..kittyFlags = _kittyFlags
        ..cursorKeyApplication = _cursorKeyApplication
        ..keypadKeyApplication = _keypadKeyApplication
        ..ignoreKeypadWithNumLock = _ignoreKeypadWithNumLock
        ..altEscPrefix = _altEscPrefix
        ..modifyOtherKeysState2 = _modifyOtherKeysState2;

      _encodedBytes = encoder.encode(event);
      _keyError = null;
    } catch (error) {
      _encodedBytes = Uint8List(0);
      _keyError = error.toString();
    } finally {
      encoder.close();
      event.close();
    }
  }

  String _asHex(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '<empty>';
    }
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  String _asEscaped(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '<empty>';
    }
    final out = StringBuffer();
    for (final b in bytes) {
      switch (b) {
        case 9:
          out.write(r'\t');
        case 10:
          out.write(r'\n');
        case 13:
          out.write(r'\r');
        case 27:
          out.write(r'\x1b');
        default:
          if (b < 32 || b == 127) {
            out.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
          } else {
            out.write(String.fromCharCode(b));
          }
      }
    }
    return out.toString();
  }

  void _applyKeyPreset({
    required GhosttyKey key,
    required String utf8,
    required int codepoint,
    required Set<int> mods,
  }) {
    setState(() {
      _selectedAction = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
      _selectedKey = key;
      _mods
        ..clear()
        ..addAll(mods);
      _consumedMods.clear();
      _utf8Controller.text = utf8;
      _codepointController.text = '0x${codepoint.toRadixString(16)}';
      _encodeKey();
      _appendLog('Applied key preset for ${key.name}.');
    });
  }

  String _describeSgr(VtSgrAttributeData attr) {
    final buffer = StringBuffer(attr.tag.name);
    if (attr.paletteIndex != null) {
      buffer.write(' (palette=${attr.paletteIndex})');
    }
    if (attr.rgb != null) {
      buffer.write(' (rgb=${attr.rgb!.r},${attr.rgb!.g},${attr.rgb!.b})');
    }
    if (attr.underline != null) {
      buffer.write(' (underline=${attr.underline!.name})');
    }
    if (attr.unknown != null) {
      buffer.write(' (unknown=${attr.unknown!.full.join(',')})');
    }
    return buffer.toString();
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'PTY Terminal',
          subtitle:
              'Run a shell process and interact through Ghostty key encoding + painter view.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _terminalController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Sample terminal input',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _computePasteSafety();
                  });
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_pasteSafe ? 'Paste safe' : 'Paste unsafe'),
                    avatar: Icon(
                      _pasteSafe ? Icons.shield_outlined : Icons.warning_amber,
                      size: 18,
                    ),
                  ),
                  Chip(
                    label: Text('${_terminalController.text.length} chars'),
                    avatar: const Icon(Icons.text_fields, size: 18),
                  ),
                  Chip(
                    label: Text(
                      _terminal.isRunning ? 'Shell running' : 'Shell stopped',
                    ),
                    avatar: Icon(
                      _terminal.isRunning
                          ? Icons.play_circle_outline
                          : Icons.stop_circle_outlined,
                      size: 18,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _terminal.isRunning ? null : _startTerminal,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Shell'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _terminal.isRunning ? _stopTerminal : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Shell'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _terminal.isRunning ? _sendTerminalInput : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Send Command'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _terminal.clear();
                      _appendLog('Cleared terminal buffer.');
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear View'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                child: GhosttyTerminalView(
                  controller: _terminal,
                  autofocus: true,
                  fontSize: 14,
                  lineHeight: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOscTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'OSC Parser Workbench',
          subtitle:
              'Parses OSC payload text and inspects command type and data.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _oscController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'OSC payload (without ESC ] ... terminator)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _parseOsc();
                  });
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('BEL (0x07)'),
                    selected: _oscTerminator == 0x07,
                    onSelected: (_) {
                      setState(() {
                        _oscTerminator = 0x07;
                        _parseOsc();
                        _appendLog('OSC parser terminator set to BEL.');
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('ST (0x5C)'),
                    selected: _oscTerminator == 0x5C,
                    onSelected: (_) {
                      setState(() {
                        _oscTerminator = 0x5C;
                        _parseOsc();
                        _appendLog('OSC parser terminator set to ST.');
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_oscError != null)
                Text('Error: $_oscError')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Type: ${_oscCommand?.type.name ?? '<none>'}'),
                    const SizedBox(height: 4),
                    Text(
                      'Window title: ${_oscCommand?.windowTitle ?? '<none>'}',
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSgrTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'SGR Parser Workbench',
          subtitle:
              'Provide parameters like 1;31;4 and inspect parsed attribute tags.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _sgrController,
                decoration: const InputDecoration(
                  labelText: 'SGR params',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _parseSgr();
                  });
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _sgrController.text = '1;31;4';
                        _parseSgr();
                        _appendLog('SGR preset applied: 1;31;4');
                      });
                    },
                    child: const Text('Preset: bold red underline'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _sgrController.text = '38;2;255;180;0';
                        _parseSgr();
                        _appendLog('SGR preset applied: truecolor fg');
                      });
                    },
                    child: const Text('Preset: truecolor fg'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_sgrError != null)
                Text('Error: $_sgrError')
              else if (_sgrAttributes.isEmpty)
                const Text('No parsed attributes.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _sgrAttributes
                      .map((attr) => Chip(label: Text(_describeSgr(attr))))
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Key Encoder Workbench',
          subtitle:
              'Configure key event + encoder options, then inspect encoded bytes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<GhosttyKeyAction>(
                      initialValue: _selectedAction,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        border: OutlineInputBorder(),
                      ),
                      items: GhosttyKeyAction.values
                          .map(
                            (action) => DropdownMenuItem(
                              value: action,
                              child: Text(action.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedAction = value;
                          _encodeKey();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<GhosttyKey>(
                      initialValue: _selectedKey,
                      decoration: const InputDecoration(
                        labelText: 'Key',
                        border: OutlineInputBorder(),
                      ),
                      items: _keyOptions
                          .map(
                            (key) => DropdownMenuItem(
                              value: key,
                              child: Text(key.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedKey = value;
                          _encodeKey();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _utf8Controller,
                decoration: const InputDecoration(
                  labelText: 'UTF-8 text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _encodeKey();
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codepointController,
                decoration: const InputDecoration(
                  labelText: 'Unshifted codepoint (decimal or 0xNN)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {
                    _encodeKey();
                  });
                },
              ),
              const SizedBox(height: 12),
              const Text('Modifiers'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _modOptions.map((option) {
                  final selected = _mods.contains(option.mask);
                  return FilterChip(
                    label: Text(option.label),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _mods.add(option.mask);
                        } else {
                          _mods.remove(option.mask);
                        }
                        _encodeKey();
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text('Consumed modifiers'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _modOptions.map((option) {
                  final selected = _consumedMods.contains(option.mask);
                  return FilterChip(
                    label: Text(option.label),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _consumedMods.add(option.mask);
                        } else {
                          _consumedMods.remove(option.mask);
                        }
                        _encodeKey();
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _composing,
                title: const Text('Composing'),
                onChanged: (value) {
                  setState(() {
                    _composing = value;
                    _encodeKey();
                  });
                },
              ),
              const Divider(),
              const Text('Encoder options'),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _cursorKeyApplication,
                title: const Text('Cursor key application'),
                onChanged: (value) {
                  setState(() {
                    _cursorKeyApplication = value;
                    _encodeKey();
                  });
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _keypadKeyApplication,
                title: const Text('Keypad key application'),
                onChanged: (value) {
                  setState(() {
                    _keypadKeyApplication = value;
                    _encodeKey();
                  });
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _ignoreKeypadWithNumLock,
                title: const Text('Ignore keypad with NumLock'),
                onChanged: (value) {
                  setState(() {
                    _ignoreKeypadWithNumLock = value;
                    _encodeKey();
                  });
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _altEscPrefix,
                title: const Text('Alt ESC prefix'),
                onChanged: (value) {
                  setState(() {
                    _altEscPrefix = value;
                    _encodeKey();
                  });
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _modifyOtherKeysState2,
                title: const Text('modifyOtherKeys mode 2'),
                onChanged: (value) {
                  setState(() {
                    _modifyOtherKeysState2 = value;
                    _encodeKey();
                  });
                },
              ),
              const SizedBox(height: 8),
              const Text('Kitty flags'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kittyFlagOptions.map((option) {
                  final selected = (_kittyFlags & option.mask) != 0;
                  return FilterChip(
                    label: Text(option.label),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _kittyFlags |= option.mask;
                        } else {
                          _kittyFlags &= ~option.mask;
                        }
                        _encodeKey();
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _applyKeyPreset(
                      key: GhosttyKey.GHOSTTY_KEY_C,
                      utf8: 'c',
                      codepoint: 0x63,
                      mods: <int>{GhosttyModsMask.ctrl},
                    ),
                    child: const Text('Preset Ctrl+C'),
                  ),
                  OutlinedButton(
                    onPressed: () => _applyKeyPreset(
                      key: GhosttyKey.GHOSTTY_KEY_ENTER,
                      utf8: '\n',
                      codepoint: 0x0D,
                      mods: <int>{},
                    ),
                    child: const Text('Preset Enter'),
                  ),
                  OutlinedButton(
                    onPressed: () => _applyKeyPreset(
                      key: GhosttyKey.GHOSTTY_KEY_ARROW_UP,
                      utf8: '',
                      codepoint: 0x00,
                      mods: <int>{},
                    ),
                    child: const Text('Preset Arrow Up'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_keyError != null)
                Text('Error: $_keyError')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bytes (hex): ${_asHex(_encodedBytes)}'),
                    const SizedBox(height: 4),
                    Text('Escaped: ${_asEscaped(_encodedBytes)}'),
                    const SizedBox(height: 4),
                    Text('Byte count: ${_encodedBytes.length}'),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityPanel() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Activity Log',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _activity.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _activity.isEmpty
                  ? const Center(child: Text('No activity yet.'))
                  : ListView.builder(
                      itemCount: _activity.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _activity[index],
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oscType = _oscCommand?.type.name ?? 'n/a';
    final oscTitle = _oscCommand?.windowTitle ?? '<none>';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A1018), Color(0xFF102129), Color(0xFF1B0E14)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0x66000000),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.memory_outlined),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ghostty VT Studio',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Advanced playground for paste safety, OSC parsing, SGR attributes, and key encoding.',
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _recomputeAll();
                            });
                          },
                          icon: const Icon(Icons.bolt_outlined),
                          label: const Text('Evaluate All'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildMetric(
                        icon: Icons.shield_outlined,
                        label: 'Paste Safety',
                        value: _pasteSafe ? 'Safe' : 'Unsafe',
                        color: _pasteSafe ? Colors.greenAccent : Colors.orange,
                      ),
                      _buildMetric(
                        icon: Icons.terminal,
                        label: 'OSC Command',
                        value: '$oscType / $oscTitle',
                        color: Colors.cyanAccent,
                      ),
                      _buildMetric(
                        icon: Icons.format_paint_outlined,
                        label: 'SGR Attributes',
                        value: '${_sgrAttributes.length} parsed',
                        color: Colors.amberAccent,
                      ),
                      _buildMetric(
                        icon: Icons.keyboard_alt_outlined,
                        label: 'Encoded Bytes',
                        value: '${_encodedBytes.length} bytes',
                        color: Colors.pinkAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1100;

                        final tabs = Theme(
                          data: Theme.of(context),
                          child: Builder(
                            builder: (context) {
                              return TabBarView(
                                children: [
                                  _buildTerminalTab(),
                                  _buildOscTab(),
                                  _buildSgrTab(),
                                  _buildKeyTab(),
                                ],
                              );
                            },
                          ),
                        );

                        final workbenchWithTabs = Column(
                          children: [
                            TabBar(
                              isScrollable: true,
                              tabs: const [
                                Tab(
                                  icon: Icon(Icons.terminal),
                                  text: 'Terminal',
                                ),
                                Tab(icon: Icon(Icons.route), text: 'OSC'),
                                Tab(icon: Icon(Icons.brush), text: 'SGR'),
                                Tab(
                                  icon: Icon(Icons.keyboard),
                                  text: 'Key Encoder',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(child: tabs),
                          ],
                        );

                        if (wide) {
                          return Row(
                            children: [
                              Expanded(child: workbenchWithTabs),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 340,
                                child: _buildActivityPanel(),
                              ),
                            ],
                          );
                        }

                        if (constraints.maxHeight < 460) {
                          return workbenchWithTabs;
                        }

                        final logHeight = (constraints.maxHeight * 0.28).clamp(
                          140.0,
                          220.0,
                        );
                        return Column(
                          children: [
                            Expanded(child: workbenchWithTabs),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: logHeight,
                              child: _buildActivityPanel(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ModOption {
  const _ModOption(this.label, this.mask);

  final String label;
  final int mask;
}

class _FlagOption {
  const _FlagOption(this.label, this.mask);

  final String label;
  final int mask;
}
