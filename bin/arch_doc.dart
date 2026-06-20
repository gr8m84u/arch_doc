import 'dart:io';

import 'package:args/args.dart';
import 'package:arch_doc/arch_doc.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'root',
      defaultsTo: Directory.current.path,
      help: 'Workspace root to analyze.',
    )
    ..addOption('config', help: 'Path to arch_doc.yaml.')
    ..addCommand(
      'generate',
      ArgParser()
        ..addFlag(
          'check',
          negatable: false,
          help: 'Check if generated files match current ones.',
        )
        ..addOption(
          'dependency-source',
          allowed: ['declared', 'used'],
          defaultsTo: 'declared',
          help: 'Source of dependencies for diagrams.',
        ),
    )
    ..addCommand('validate');

  final results = parser.parse(args);

  if (results.command == null) {
    print('Usage: arch_doc <command> [options]');
    print(
      '       arch_doc [--root <path>] [--config <path>] <command> [options]',
    );
    print('Commands:');
    print('  generate [--check] [--dependency-source <declared|used>]');
    print('  validate');
    exit(1);
  }

  final command = switch (results.command!.name) {
    'generate' => ArchDocCommand.generate,
    'validate' => ArchDocCommand.validate,
    _ => null,
  };
  if (command == null) {
    print('Usage: arch_doc <command> [options]');
    exit(1);
  }

  final generateResults = results.command!;
  final depSourceStr = command == ArchDocCommand.generate
      ? generateResults['dependency-source'] as String
      : 'declared';
  final depSource = depSourceStr == 'used'
      ? DependencySource.used
      : DependencySource.declared;
  final rootPath = Directory(results['root'] as String).absolute.path;
  final configPath = results['config'] as String?;

  final result = await ArchDocRunner().run(
    ArchDocOptions(
      command: command,
      rootPath: rootPath,
      check: command == ArchDocCommand.generate
          ? generateResults['check'] as bool
          : false,
      dependencySource: depSource,
      configPath: configPath,
    ),
  );

  for (final line in result.stdout) {
    print(line);
  }
  exitCode = result.exitCode;
}
