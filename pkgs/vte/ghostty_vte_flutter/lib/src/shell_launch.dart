library;

import 'platform_shell_lookup_stub.dart'
    if (dart.library.io) 'platform_shell_lookup_io.dart'
    as platform_shell;
import 'shell_environment.dart';

/// Shared shell profiles used by the example apps and terminal demos.
enum GhosttyTerminalShellProfile { auto, cleanBash, cleanZsh, userShell }

extension GhosttyTerminalShellProfileLabel on GhosttyTerminalShellProfile {
  /// User-facing label for the profile.
  String get label => switch (this) {
    GhosttyTerminalShellProfile.auto => 'Auto',
    GhosttyTerminalShellProfile.cleanBash => 'Bash',
    GhosttyTerminalShellProfile.cleanZsh => 'Zsh',
    GhosttyTerminalShellProfile.userShell => 'User Shell',
  };
}

/// A resolved shell launch plan with a normalized environment.
final class GhosttyTerminalShellLaunch {
  const GhosttyTerminalShellLaunch({
    required this.label,
    required this.shell,
    this.arguments = const <String>[],
    this.environment,
    this.setupCommand,
  });

  final String label;
  final String shell;
  final List<String> arguments;
  final Map<String, String>? environment;
  final String? setupCommand;

  /// Human-readable shell command for diagnostics and example UIs.
  String get commandLine {
    if (arguments.isEmpty) {
      return shell;
    }
    return '$shell ${arguments.join(' ')}';
  }
}

/// Resolves one or more native shell launch plans for a given profile.
///
/// The returned launches already include a normalized environment via
/// [ghosttyTerminalShellEnvironment].
List<GhosttyTerminalShellLaunch> ghosttyTerminalShellLaunches({
  required GhosttyTerminalShellProfile profile,
  Map<String, String>? platformEnvironment,
  Map<String, String> environmentOverrides = const <String, String>{
    'TERM': 'xterm-256color',
  },
  GhosttyTerminalShellEnvironmentOptions environmentOptions =
      const GhosttyTerminalShellEnvironmentOptions(),
  bool includeSetupCommands = true,
}) {
  final effectivePlatformEnvironment =
      platformEnvironment ?? ghosttyTerminalPlatformEnvironment();
  final shellEnvironment = ghosttyTerminalShellEnvironment(
    platformEnvironment: effectivePlatformEnvironment,
    overrides: environmentOverrides,
    options: environmentOptions,
  );

  if (platform_shell.ghosttyTerminalPlatformIsWindows()) {
    final command = effectivePlatformEnvironment['ComSpec'];
    if (command == null || command.isEmpty) {
      return const <GhosttyTerminalShellLaunch>[];
    }
    return <GhosttyTerminalShellLaunch>[
      GhosttyTerminalShellLaunch(
        label: 'cmd.exe',
        shell: command,
        environment: shellEnvironment,
      ),
    ];
  }

  GhosttyTerminalShellLaunch? bashLaunch() {
    final bash = platform_shell.ghosttyTerminalResolveFirstExistingShell(
      const <String>['/bin/bash', '/usr/bin/bash'],
    );
    if (bash == null) {
      return null;
    }
    return GhosttyTerminalShellLaunch(
      label: 'clean bash shell',
      shell: bash,
      arguments: const <String>['--noprofile', '--norc', '-i'],
      environment: shellEnvironment,
      setupCommand: includeSetupCommands ? "export PS1='> '\n" : null,
    );
  }

  GhosttyTerminalShellLaunch? zshLaunch() {
    final zsh = platform_shell.ghosttyTerminalResolveFirstExistingShell(
      const <String>['/bin/zsh', '/usr/bin/zsh'],
    );
    if (zsh == null) {
      return null;
    }
    return GhosttyTerminalShellLaunch(
      label: 'clean zsh shell',
      shell: zsh,
      arguments: const <String>['-f', '-i'],
      environment: shellEnvironment,
      setupCommand: includeSetupCommands
          ? "PROMPT='%# '\nRPROMPT=\nunsetopt TRANSIENT_RPROMPT\n"
                "stty erase '^?'\n"
                "bindkey '^?' backward-delete-char\n"
                "bindkey '^H' backward-delete-char\n"
          : null,
    );
  }

  GhosttyTerminalShellLaunch? shLaunch() {
    final sh = platform_shell.ghosttyTerminalResolveFirstExistingShell(
      const <String>['/bin/sh', '/usr/bin/sh'],
    );
    if (sh == null) {
      return null;
    }
    return GhosttyTerminalShellLaunch(
      label: 'clean sh shell',
      shell: sh,
      arguments: const <String>['-i'],
      environment: shellEnvironment,
      setupCommand: includeSetupCommands ? "PS1='> '\n" : null,
    );
  }

  GhosttyTerminalShellLaunch? userShellLaunch() {
    final shell = effectivePlatformEnvironment['SHELL'];
    if (shell == null || shell.isEmpty) {
      return null;
    }
    return GhosttyTerminalShellLaunch(
      label: 'user shell',
      shell: shell,
      arguments: const <String>['-i'],
      environment: shellEnvironment,
    );
  }

  List<GhosttyTerminalShellLaunch> maybeLaunch(
    GhosttyTerminalShellLaunch? launch,
  ) {
    if (launch == null) {
      return const <GhosttyTerminalShellLaunch>[];
    }
    return <GhosttyTerminalShellLaunch>[launch];
  }

  return switch (profile) {
    GhosttyTerminalShellProfile.auto => <GhosttyTerminalShellLaunch>[
      ...maybeLaunch(bashLaunch()),
      ...maybeLaunch(zshLaunch()),
      ...maybeLaunch(shLaunch()),
    ],
    GhosttyTerminalShellProfile.cleanBash => <GhosttyTerminalShellLaunch>[
      ...maybeLaunch(bashLaunch()),
    ],
    GhosttyTerminalShellProfile.cleanZsh => <GhosttyTerminalShellLaunch>[
      ...maybeLaunch(zshLaunch()),
    ],
    GhosttyTerminalShellProfile.userShell => <GhosttyTerminalShellLaunch>[
      ...maybeLaunch(userShellLaunch()),
    ],
  };
}
