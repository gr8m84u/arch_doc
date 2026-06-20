import 'dart:io';

import 'package:arch_doc/arch_doc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArchDocRunner', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('arch_doc_runner_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'generate writes documentation and check reports up to date',
      () async {
        _writePackage(tempDir, 'pkg_core');
        _writeConfig(
          tempDir,
          layers: {
            'core': ['pkg_core'],
            'contracts': <String>[],
            'implementations': <String>[],
          },
        );

        final runner = ArchDocRunner();
        final generate = await runner.run(
          ArchDocOptions(
            command: ArchDocCommand.generate,
            rootPath: tempDir.path,
          ),
        );
        expect(generate.exitCode, 0);
        expect(
          _normalized(generate.stdout),
          contains('Generated: doc/arch_doc/README.md'),
        );
        expect(
          File(
            p.join(tempDir.path, 'doc', 'arch_doc', 'README.md'),
          ).existsSync(),
          isTrue,
        );

        final check = await runner.run(
          ArchDocOptions(
            command: ArchDocCommand.generate,
            rootPath: tempDir.path,
            check: true,
          ),
        );
        expect(check.exitCode, 0);
        expect(
          check.stdout,
          contains('Architecture documentation is up to date.'),
        );
      },
    );

    test('generate --check reports mismatches', () async {
      _writePackage(tempDir, 'pkg_core');
      _writeConfig(
        tempDir,
        layers: {
          'core': ['pkg_core'],
          'contracts': <String>[],
          'implementations': <String>[],
        },
      );

      final runner = ArchDocRunner();
      await runner.run(
        ArchDocOptions(
          command: ArchDocCommand.generate,
          rootPath: tempDir.path,
        ),
      );
      File(
        p.join(tempDir.path, 'doc', 'arch_doc', 'README.md'),
      ).writeAsStringSync('stale');

      final check = await runner.run(
        ArchDocOptions(
          command: ArchDocCommand.generate,
          rootPath: tempDir.path,
          check: true,
        ),
      );
      expect(check.exitCode, 1);
      expect(
        _normalized(check.stdout),
        contains('MISMATCH: doc/arch_doc/README.md'),
      );
      expect(
        check.stdout,
        contains('Architecture documentation is out of date.'),
      );
      expect(
        check.stdout,
        contains(r'Run "dart run arch_doc generate" to update.'),
      );
    });

    test(
      'uses arch_doc.yaml from workspace root before legacy config',
      () async {
        _writePackage(tempDir, 'pkg_core');
        _writeRootConfig(
          tempDir,
          layers: {
            'root_layer': ['pkg_core'],
          },
        );

        final result = await ArchDocRunner().run(
          ArchDocOptions(
            command: ArchDocCommand.generate,
            rootPath: tempDir.path,
          ),
        );

        expect(result.exitCode, 0);
        expect(
          result.model?.packages.map((package) => package.name),
          contains('pkg_core'),
        );
      },
    );

    test('uses explicit config path', () async {
      _writePackage(tempDir, 'pkg_core');
      final config = _writeRootConfig(
        tempDir,
        fileName: 'custom_arch_doc.yaml',
        layers: {
          'custom_layer': ['pkg_core'],
        },
      );

      final result = await ArchDocRunner().run(
        ArchDocOptions(
          command: ArchDocCommand.validate,
          rootPath: tempDir.path,
          configPath: config.path,
        ),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains(startsWith('Observations:')));
    });

    test('validate reports missing config with Windows example', () async {
      _writePackage(tempDir, 'pkg_core');

      final result = await ArchDocRunner().run(
        ArchDocOptions(
          command: ArchDocCommand.validate,
          rootPath: tempDir.path,
        ),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, contains('Configuration file not found.'));
      expect(
        result.stdout,
        contains(
          r'Example: dart run arch_doc --config C:\path\to\arch_doc.yaml validate',
        ),
      );
    });

    test('generate --check reports orphan API files', () async {
      _writePackage(tempDir, 'pkg_core');
      _writeConfig(
        tempDir,
        layers: {
          'core': ['pkg_core'],
          'contracts': <String>[],
          'implementations': <String>[],
        },
      );

      final runner = ArchDocRunner();
      await runner.run(
        ArchDocOptions(
          command: ArchDocCommand.generate,
          rootPath: tempDir.path,
        ),
      );
      final orphan = File(
        p.join(tempDir.path, 'doc', 'arch_doc', 'api', 'removed_pkg.md'),
      );
      orphan.writeAsStringSync('orphan');

      final check = await runner.run(
        ArchDocOptions(
          command: ArchDocCommand.generate,
          rootPath: tempDir.path,
          check: true,
        ),
      );
      expect(check.exitCode, 1);
      expect(
        _normalized(check.stdout),
        contains('ORPHAN: doc/arch_doc/api/removed_pkg.md'),
      );
    });

    test('validate exits 1 for layer errors', () async {
      _writePackage(tempDir, 'pkg_core', dependencies: ['pkg_impl']);
      _writePackage(tempDir, 'pkg_impl');
      _writeConfig(
        tempDir,
        layers: {
          'core': ['pkg_core'],
          'contracts': <String>[],
          'implementations': ['pkg_impl'],
        },
      );

      final result = await ArchDocRunner().run(
        ArchDocOptions(
          command: ArchDocCommand.validate,
          rootPath: tempDir.path,
        ),
      );

      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains('Architecture validation completed with findings.'),
      );
      expect(result.stdout, contains(startsWith('Errors:')));
    });

    test('validate exits 0 for warnings and observations only', () async {
      _writePackage(tempDir, 'pkg_core');
      _writeConfig(
        tempDir,
        layers: {
          'core': ['pkg_core'],
          'contracts': <String>[],
          'implementations': <String>[],
        },
      );

      final result = await ArchDocRunner().run(
        ArchDocOptions(
          command: ArchDocCommand.validate,
          rootPath: tempDir.path,
        ),
      );

      expect(result.exitCode, 0);
      expect(result.stdout, contains(startsWith('Observations:')));
    });

    test('validate applies risk policy promotion', () async {
      _writePackage(tempDir, 'pkg_core');
      _writeConfig(
        tempDir,
        layers: {
          'core': ['pkg_core'],
          'contracts': <String>[],
          'implementations': <String>[],
        },
        failOnObservations: true,
      );

      final result = await ArchDocRunner().run(
        ArchDocOptions(
          command: ArchDocCommand.validate,
          rootPath: tempDir.path,
        ),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, contains(startsWith('Errors:')));
    });
  });
}

void _writePackage(
  Directory root,
  String name, {
  List<String> dependencies = const [],
}) {
  final packageDir = Directory(p.join(root.path, 'packages', name))
    ..createSync(recursive: true);
  final dependencyYaml = dependencies.isEmpty
      ? ''
      : '''
dependencies:
${dependencies.map((dependency) => '  $dependency:\n    path: ../$dependency').join('\n')}
''';
  File(p.join(packageDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
description: Test package $name.
$dependencyYaml
''');
  final libDir = Directory(p.join(packageDir.path, 'lib'))..createSync();
  File(p.join(libDir.path, '$name.dart')).writeAsStringSync('''
${dependencies.map((dependency) => "import 'package:$dependency/$dependency.dart';").join('\n')}
class ${_className(name)} {}
''');
}

List<String> _normalized(List<String> lines) {
  return lines.map((line) => line.replaceAll('\\', '/')).toList();
}

void _writeConfig(
  Directory root, {
  required Map<String, List<String>> layers,
  bool failOnObservations = false,
}) {
  final configDir = Directory(p.join(root.path, 'tools', 'arch_doc', 'config'))
    ..createSync(recursive: true);
  File(p.join(configDir.path, 'arch_doc.yaml')).writeAsStringSync('''
output:
  root: doc/arch_doc

layers:
${layers.entries.map((entry) => _layerYaml(entry.key, entry.value)).join('\n')}

rules:
  - name: core_must_not_depend_on_implementations
    from_layer: core
    forbidden_layers:
      - implementations

excluded_packages:
  - arch_doc

api_rules:
  require_public_entrypoint: true
  forbid_exports_from_src: false
  warn_internal_public_declarations: true
  max_exported_symbols_per_package: null

component_rules:
  require_known_responsibility: true
  warn_without_public_api: true
  warn_without_dependents: true
  warn_without_dependencies: true

contract_analysis:
  enabled: true
  detect_protocols: true
  include_lld_methods: true
  unwrap_async_types: true
  max_methods_per_contract: 50
  warn_without_consumers: false

risk_rules:
  fail_on_risks: false
  fail_on_warnings: false
  fail_on_observations: $failOnObservations
''');
}

File _writeRootConfig(
  Directory root, {
  String fileName = 'arch_doc.yaml',
  required Map<String, List<String>> layers,
}) {
  final file = File(p.join(root.path, fileName));
  file.writeAsStringSync('''
output:
  root: doc/arch_doc

layers:
${layers.entries.map((entry) => _layerYaml(entry.key, entry.value)).join('\n')}

rules: []

excluded_packages: []

api_rules:
  require_public_entrypoint: true
  forbid_exports_from_src: false
  warn_internal_public_declarations: true
  max_exported_symbols_per_package: null

component_rules:
  require_known_responsibility: true
  warn_without_public_api: true
  warn_without_dependents: true
  warn_without_dependencies: true

contract_analysis:
  enabled: true
  detect_protocols: true
  include_lld_methods: true
  unwrap_async_types: true
  max_methods_per_contract: 50
  warn_without_consumers: false

risk_rules:
  fail_on_risks: false
  fail_on_warnings: false
  fail_on_observations: false
''');
  return file;
}

String _layerYaml(String name, List<String> packages) {
  final packageLines = packages.isEmpty
      ? '      []'
      : packages.map((package) => '      - $package').join('\n');
  return '''
  $name:
    packages:
$packageLines
''';
}

String _className(String packageName) {
  return packageName
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
}
