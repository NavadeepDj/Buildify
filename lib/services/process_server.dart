import 'dart:convert';
import 'dart:io';

class ProcessServer {
  Process? _process;
  final String command;
  final String workingDirectory;
  final int port;
  final Map<String, String> environment;
  final void Function(String message, {bool isError})? onLog;

  ProcessServer({
    required this.command,
    required this.workingDirectory,
    required this.port,
    this.environment = const {},
    this.onLog,
  });

  bool get isRunning => _process != null;

  /// Host environment variables that are safe/necessary to forward to a child
  /// build process. Everything else in [Platform.environment] is withheld so a
  /// hosted project (or a malicious dependency it pulls in) can't read secrets,
  /// tokens, or unrelated host configuration from the process environment.
  static const _allowedEnvKeys = {
    // POSIX / Android essentials
    'path', 'home', 'tmpdir', 'lang', 'lc_all', 'lc_ctype', 'term', 'user',
    'logname', 'shell', 'tz', 'ld_library_path', 'android_root', 'android_data',
    'android_storage', 'external_storage', 'bootclasspath',
    // Windows essentials
    'pathext', 'systemroot', 'systemdrive', 'comspec', 'windir', 'temp', 'tmp',
    'userprofile', 'homedrive', 'homepath', 'appdata', 'localappdata',
    'programfiles',
    'programfiles(x86)',
    'programdata',
    'processor_architecture',
    'number_of_processors', 'os', 'username', 'computername',
  };

  /// Builds the child environment: a curated slice of the host environment,
  /// with the injected [port] and caller-supplied [extra] vars layered on top.
  static Map<String, String> buildChildEnvironment(
    int port,
    Map<String, String> extra,
  ) {
    final env = <String, String>{};
    Platform.environment.forEach((key, value) {
      if (_allowedEnvKeys.contains(key.toLowerCase())) {
        env[key] = value;
      }
    });
    env['PORT'] = '$port';
    env.addAll(extra);
    return env;
  }

  Future<void> start() async {
    if (_process != null) return;

    onLog?.call('[server] starting process: $command');

    final env = buildChildEnvironment(port, environment);

    try {
      if (Platform.isWindows) {
        // cmd.exe does not understand Dart's backslash quote escaping. Expand
        // the intentionally user-authored command inside cmd instead, preserving
        // executable/argument paths containing spaces. No host secrets are added.
        _process = await Process.start(
          'cmd',
          ['/d', '/c', '%BUILDIFY_PROCESS_COMMAND%'],
          workingDirectory: workingDirectory,
          environment: {...env, 'BUILDIFY_PROCESS_COMMAND': command},
          includeParentEnvironment: false,
          runInShell: false,
        );
      } else {
        _process = await Process.start(
          '/system/bin/sh',
          ['-c', command],
          workingDirectory: workingDirectory,
          environment: env,
          includeParentEnvironment: false,
        );
      }
    } catch (_) {
      // Fallback: let the OS resolve sh/cmd
      _process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        [Platform.isWindows ? '/c' : '-c', command],
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: false,
        runInShell: true,
      );
    }

    final startedProcess = _process!;
    startedProcess.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog?.call('[stdout] $line'));

    startedProcess.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog?.call('[stderr] $line', isError: true));

    startedProcess.exitCode.then((code) {
      onLog?.call(
        '[server] process exited with code $code',
        isError: code != 0,
      );
      if (identical(_process, startedProcess)) _process = null;
    });
  }

  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    if (Platform.isWindows) {
      // cmd.exe is only the project command launcher. Kill its owned process
      // tree so Node/Python children do not keep the project port bound.
      final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      await Process.run('$root\\System32\\taskkill.exe', [
        '/PID',
        '${proc.pid}',
        '/T',
        '/F',
      ], runInShell: false);
    } else {
      proc.kill(ProcessSignal.sigterm);
    }
    // Give it 3 seconds to exit gracefully before force-killing
    await Future.any([
      proc.exitCode,
      Future.delayed(const Duration(seconds: 3)),
    ]);
    try {
      proc.kill(ProcessSignal.sigkill);
    } catch (_) {}
    if (identical(_process, proc)) _process = null;
  }

  /// Runs a build command to completion and streams its output.
  /// Returns true on exit code 0, false otherwise.
  static Future<bool> runBuild({
    required String command,
    required String workingDirectory,
    required Map<String, String> environment,
    required void Function(String, {bool isError}) onLog,
  }) async {
    onLog('[build] \$ $command');

    // Curated host env (no port injection needed for a one-shot build) plus
    // the caller-supplied vars.
    final env = <String, String>{};
    Platform.environment.forEach((key, value) {
      if (_allowedEnvKeys.contains(key.toLowerCase())) env[key] = value;
    });
    env.addAll(environment);

    Process process;
    try {
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd',
          ['/d', '/c', '%BUILDIFY_PROCESS_COMMAND%'],
          workingDirectory: workingDirectory,
          environment: {...env, 'BUILDIFY_PROCESS_COMMAND': command},
          includeParentEnvironment: false,
          runInShell: false,
        );
      } else {
        process = await Process.start(
          '/system/bin/sh',
          ['-c', command],
          workingDirectory: workingDirectory,
          environment: env,
          includeParentEnvironment: false,
        );
      }
    } catch (_) {
      process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        [Platform.isWindows ? '/c' : '-c', command],
        workingDirectory: workingDirectory,
        environment: env,
        includeParentEnvironment: false,
        runInShell: true,
      );
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog('[build] $line'));

    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((line) => onLog('[build] $line', isError: true));

    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      onLog('[build] completed successfully (exit 0)');
      return true;
    } else {
      onLog('[build] failed — exit code $exitCode', isError: true);
      return false;
    }
  }
}
