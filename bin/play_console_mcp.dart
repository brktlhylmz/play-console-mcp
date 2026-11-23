import 'dart:io';

import 'package:play_console_mcp/play_console_mcp.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--version') || arguments.contains('-v')) {
    stdout.writeln('play-console-mcp $playConsoleMcpVersion');
    return;
  }

  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printHelp();
    return;
  }

  if (arguments.contains('--install-skill')) {
    _installSkill();
    return;
  }

  final app = PlayConsoleMcpApp();
  try {
    if (arguments.contains('--doctor')) {
      final profileOverride = _readFlagValue(arguments, '--profile');
      final packageOverride = _readFlagValue(arguments, '--package');
      final bucketOverride = _readFlagValue(arguments, '--bucket');
      final ctx = app.profileStore.resolveContext(<String, Object?>{
        if (profileOverride != null) 'profile': profileOverride,
      });
      final report = await app.profileTools.runDoctor(
        ctx,
        packageName: packageOverride ?? ctx.defaultPackageName,
        bucketName: bucketOverride ?? ctx.gcsBucketId,
      );
      stdout.writeln(prettyJson(report));
      if (report['healthy'] != true) {
        exitCode = 1;
      }
      return;
    }

    await app.server.serve();
  } finally {
    app.close();
  }
}

String? _readFlagValue(List<String> args, String flag) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == flag && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$flag=')) {
      return arg.substring(flag.length + 1);
    }
  }
  return null;
}

void _installSkill() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (home.isEmpty) {
    stderr.writeln('Unable to determine HOME directory for skill install.');
    exitCode = 1;
    return;
  }
  final roots = <String>[
    '$home/.gemini/config/skills',
    if (Directory('$home/.claude').existsSync()) '$home/.claude/skills',
  ];
  for (final root in roots) {
    final skillFile = File('$root/play-console-mcp/SKILL.md');
    if (!skillFile.parent.existsSync()) {
      skillFile.parent.createSync(recursive: true);
    }
    skillFile.writeAsStringSync(playConsoleAgentSkillMarkdown);
    stdout.writeln('Installed skill: ${skillFile.path}');
  }
}

void _printHelp() {
  stdout.writeln('''
play-console-mcp $playConsoleMcpVersion — Google Play Console MCP Server (MIT)

Usage:
  play-console-mcp                  Start MCP JSON-RPC 2.0 server over stdio
  play-console-mcp --doctor         Verify Service Account credentials & Play APIs
    [--profile <id>] [--package <com.example.app>] [--bucket <pubsite_prod_rev_...>]
  play-console-mcp --install-skill  Install optional agent SKILL.md to ~/.gemini / ~/.claude
  play-console-mcp --version | -v   Print version
  play-console-mcp --help | -h      Print this help

Environment Variables:
  PLAY_CONSOLE_PROFILE                       Default profile ID in ~/.config/play_console_mcp/config.json
  PLAY_CONSOLE_SERVICE_ACCOUNT_PATH          Path to Google Cloud Service Account JSON key
  PLAY_CONSOLE_SERVICE_ACCOUNT_JSON          Inline Service Account JSON key string (for CI/containers)
  GOOGLE_APPLICATION_CREDENTIALS             Standard Google ADC Service Account JSON path
  PLAY_CONSOLE_DEFAULT_PACKAGE               Default Android packageName
  PLAY_CONSOLE_DEVELOPER_ID                  Default Play Console developer account ID
  PLAY_CONSOLE_GCS_BUCKET                    Default Play reports GCS bucket (pubsite_prod_rev_*)
  PLAY_CONSOLE_READ_ONLY                     Set "true" to block all mutating tools
  PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES       Set "true" to allow production/destructive writes without confirm flags
  PLAY_CONSOLE_CHANGES_NOT_SENT_FOR_REVIEW   Set "true" to default edits.commit to changesNotSentForReview=true
''');
}
