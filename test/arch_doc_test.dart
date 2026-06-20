import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('WorkspaceAnalyzer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('arch_doc_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('parses pubspec correctly with various dependency types', () async {
      final pkgDir = Directory(p.join(tempDir.path, 'pkg1'))..createSync();
      File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: pkg1
description: Test package
dependencies:
  pkg2:
    path: ../pkg2
  external: ^1.0.0
dev_dependencies:
  test_pkg:
    path: ../test_pkg
dependency_overrides:
  override_pkg:
    path: ../../override_pkg
''');

      final analyzer = WorkspaceAnalyzer(tempDir.path);
      final nodes = await analyzer.analyze();

      expect(nodes, hasLength(1));
      final node = nodes.first;
      expect(node.name, 'pkg1');
      expect(node.declaredDependencies, ['pkg2']);
      expect(node.devDependencies, ['test_pkg']);
      expect(node.dependencyOverrides, ['override_pkg']);
    });

    test('ignores specified patterns', () async {
      final pkg1 = Directory(p.join(tempDir.path, 'packages', 'pkg1'))
        ..createSync(recursive: true);
      File(p.join(pkg1.path, 'pubspec.yaml')).writeAsStringSync('name: pkg1');

      final dartTool = Directory(
        p.join(tempDir.path, 'packages', 'pkg1', '.dart_tool'),
      )..createSync();
      File(
        p.join(dartTool.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: ignored_dart_tool');

      final buildDir = Directory(
        p.join(tempDir.path, 'packages', 'pkg1', 'build'),
      )..createSync();
      File(
        p.join(buildDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: ignored_build');

      final archDocDir = Directory(p.join(tempDir.path, 'tools', 'arch_doc'))
        ..createSync(recursive: true);
      File(
        p.join(archDocDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: arch_doc');

      final analyzer = WorkspaceAnalyzer(tempDir.path);
      final nodes = await analyzer.analyze();

      expect(nodes.map((e) => e.name), contains('pkg1'));
      expect(nodes.map((e) => e.name), isNot(contains('ignored_dart_tool')));
      expect(nodes.map((e) => e.name), isNot(contains('ignored_build')));
      expect(nodes.map((e) => e.name), isNot(contains('arch_doc')));
    });

    test('sorts nodes alphabetically', () async {
      final pkgB = Directory(p.join(tempDir.path, 'pkgB'))..createSync();
      File(p.join(pkgB.path, 'pubspec.yaml')).writeAsStringSync('name: pkgB');

      final pkgA = Directory(p.join(tempDir.path, 'pkgA'))..createSync();
      File(p.join(pkgA.path, 'pubspec.yaml')).writeAsStringSync('name: pkgA');

      final analyzer = WorkspaceAnalyzer(tempDir.path);
      final nodes = await analyzer.analyze();

      expect(nodes[0].name, 'pkgA');
      expect(nodes[1].name, 'pkgB');
    });

    test('discovers external package from root workspace entry', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final external = Directory(p.join(parent.path, 'external', 'pkg_ext'))
          ..createSync(recursive: true);
        _writePubspec(root, '''
name: root_pkg
workspace:
  - ../external/pkg_ext
''');
        _writePubspec(external, 'name: pkg_ext');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.findings, isEmpty);
        expect(result.nodes.map((node) => node.name), ['pkg_ext', 'root_pkg']);
        final externalNode = result.nodes.firstWhere(
          (node) => node.name == 'pkg_ext',
        );
        expect(externalNode.isExternal, isTrue);
        expect(externalNode.relativePath, '../external/pkg_ext');
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('discovers external package from path dependency', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final app = Directory(p.join(root.path, 'app'))..createSync();
        final external = Directory(p.join(parent.path, 'shared', 'models'))
          ..createSync(recursive: true);
        _writePubspec(app, '''
name: app
dependencies:
  models:
    path: ../../shared/models
''');
        _writePubspec(external, 'name: models');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.findings, isEmpty);
        expect(result.nodes.map((node) => node.name), ['app', 'models']);
        expect(
          result.nodes.firstWhere((node) => node.name == 'models').isExternal,
          isTrue,
        );
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('discovers external package from dependency_overrides', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final app = Directory(p.join(root.path, 'app'))..createSync();
        final external = Directory(p.join(parent.path, 'override_pkg'))
          ..createSync();
        _writePubspec(app, '''
name: app
dependency_overrides:
  override_pkg:
    path: ../../override_pkg
''');
        _writePubspec(external, 'name: override_pkg');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.findings, isEmpty);
        expect(result.nodes.map((node) => node.name), ['app', 'override_pkg']);
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('ignores external path dependencies silently when disabled', () async {
      final app = Directory(p.join(tempDir.path, 'app'))..createSync();
      _writePubspec(app, '''
name: app
dependencies:
  missing:
    path: ../missing_external
''');

      final result = await WorkspaceAnalyzer(
        tempDir.path,
      ).analyzeWithFindings();

      expect(result.nodes.map((node) => node.name), ['app']);
      expect(result.findings, isEmpty);
    });

    test('reports missing external path package only when enabled', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final app = Directory(p.join(root.path, 'app'))..createSync();
        _writePubspec(app, '''
name: app
dependencies:
  missing:
    path: ../../missing_external
''');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.findings, hasLength(1));
        expect(
          result.findings.first.ruleName,
          'external_path_package_not_found',
        );
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('respects max_external_depth', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final app = Directory(p.join(root.path, 'app'))..createSync();
        final ext1 = Directory(p.join(parent.path, 'ext1'))..createSync();
        final ext2 = Directory(p.join(parent.path, 'ext2'))..createSync();
        final ext3 = Directory(p.join(parent.path, 'ext3'))..createSync();
        _writePubspec(app, '''
name: app
dependencies:
  ext1:
    path: ../../ext1
''');
        _writePubspec(ext1, '''
name: ext1
dependencies:
  ext2:
    path: ../ext2
''');
        _writePubspec(ext2, '''
name: ext2
dependencies:
  ext3:
    path: ../ext3
''');
        _writePubspec(ext3, 'name: ext3');

        Future<List<String>> namesAtDepth(int depth) async {
          final result = await WorkspaceAnalyzer(
            root.path,
            includeExternalPathPackages: true,
            maxExternalDepth: depth,
          ).analyzeWithFindings();
          return result.nodes.map((node) => node.name).toList();
        }

        expect(await namesAtDepth(0), ['app', 'ext1']);
        expect(await namesAtDepth(1), ['app', 'ext1', 'ext2']);
        expect(await namesAtDepth(2), ['app', 'ext1', 'ext2', 'ext3']);
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('reports duplicate package names from different paths', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final local = Directory(p.join(root.path, 'local_dup'))..createSync();
        final external = Directory(p.join(parent.path, 'external_dup'))
          ..createSync();
        _writePubspec(local, '''
name: dup
dependencies:
  dup:
    path: ../../external_dup
''');
        _writePubspec(external, 'name: dup');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.hasErrors, isTrue);
        final duplicate = result.findings.firstWhere(
          (finding) => finding.ruleName == 'duplicate_package_name',
        );
        expect(duplicate.reason, contains('Duplicate package name found: dup'));
        expect(duplicate.reason, contains('local_dup'));
        expect(duplicate.reason, contains('external_dup'));
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('handles recursive external path dependency cycles', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final app = Directory(p.join(root.path, 'app'))..createSync();
        final extA = Directory(p.join(parent.path, 'ext_a'))..createSync();
        final extB = Directory(p.join(parent.path, 'ext_b'))..createSync();
        _writePubspec(app, '''
name: app
dependencies:
  ext_a:
    path: ../../ext_a
''');
        _writePubspec(extA, '''
name: ext_a
dependencies:
  ext_b:
    path: ../ext_b
''');
        _writePubspec(extB, '''
name: ext_b
dependencies:
  ext_a:
    path: ../ext_a
''');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
          maxExternalDepth: 5,
        ).analyzeWithFindings();

        expect(result.findings, isEmpty);
        expect(result.nodes.map((node) => node.name), [
          'app',
          'ext_a',
          'ext_b',
        ]);
      } finally {
        await parent.delete(recursive: true);
      }
    });

    test('sorts mixed local and external packages deterministically', () async {
      final parent = await Directory.systemTemp.createTemp('arch_doc_ext_');
      try {
        final root = Directory(p.join(parent.path, 'root'))..createSync();
        final zLocal = Directory(p.join(root.path, 'z_local'))..createSync();
        final aExternal = Directory(p.join(parent.path, 'a_external'))
          ..createSync();
        _writePubspec(zLocal, '''
name: z_local
dependencies:
  a_external:
    path: ../../a_external
''');
        _writePubspec(aExternal, 'name: a_external');

        final result = await WorkspaceAnalyzer(
          root.path,
          includeExternalPathPackages: true,
        ).analyzeWithFindings();

        expect(result.nodes.map((node) => node.name), [
          'a_external',
          'z_local',
        ]);
      } finally {
        await parent.delete(recursive: true);
      }
    });
  });

  group('DocGenerator', () {
    test('generates deterministic JSON', () {
      final nodes = [
        PackageNode(
          name: 'b',
          path: 'p/b',
          description: 'desc b',
          declaredDependencies: ['a'],
          usedDependencies: ['a'],
        ),
        PackageNode(
          name: 'a',
          path: 'p/a',
          description: 'desc a',
          declaredDependencies: [],
          usedDependencies: [],
        ),
      ];
      nodes.sort((a, b) => a.name.compareTo(b.name));

      final generator = DocGenerator(nodes);
      final json = generator.generateJson();

      final expected = '''
[
  {
    "name": "a",
    "path": "p/a",
    "packagePath": "p/a",
    "isExternal": false,
    "source": "local",
    "sourceRootLabel": "local",
    "description": "desc a",
    "declaredDependencies": [],
    "usedDependencies": [],
    "unusedDeclaredDependencies": [],
    "missingDeclaredDependencies": []
  },
  {
    "name": "b",
    "path": "p/b",
    "packagePath": "p/b",
    "isExternal": false,
    "source": "local",
    "sourceRootLabel": "local",
    "description": "desc b",
    "declaredDependencies": [
      "a"
    ],
    "usedDependencies": [
      "a"
    ],
    "unusedDeclaredDependencies": [],
    "missingDeclaredDependencies": []
  }
]
''';
      expect(json.trim(), expected.trim());
    });

    test('generates Mermaid with escaped descriptions', () {
      final nodes = [
        PackageNode(
          name: 'pkg',
          path: 'path',
          description: 'desc "with quotes"',
          declaredDependencies: [],
          usedDependencies: [],
        ),
      ];
      final generator = DocGenerator(nodes);
      final mermaid = generator.generateMermaid();

      expect(
        mermaid,
        contains('pkg["pkg<br/><small>desc \\"with quotes\\"</small>"]'),
      );
    });

    test('marks external packages in Mermaid labels', () {
      final nodes = [
        PackageNode(
          name: 'external_pkg',
          path: '../external_pkg',
          description: 'External description',
          declaredDependencies: [],
          usedDependencies: [],
          isExternal: true,
        ),
      ];
      final generator = DocGenerator(nodes);

      expect(
        generator.generateMermaid(),
        contains(
          'external_pkg["external_pkg<br/><small>external path</small>"]',
        ),
      );
    });

    test('generates deterministic PlantUML package diagram', () {
      final nodes = [
        PackageNode(
          name: 'pkg_b',
          path: 'p/b',
          description: 'desc b',
          declaredDependencies: ['pkg_a'],
          usedDependencies: ['pkg_a'],
        ),
        PackageNode(
          name: 'pkg_a',
          path: 'p/a',
          description: 'desc a',
          declaredDependencies: [],
          usedDependencies: [],
        ),
      ]..sort((a, b) => a.name.compareTo(b.name));

      expect(
        DocGenerator(nodes).generatePlantUml().trim(),
        '''
@startuml
package "Packages" {
  component "pkg_a" as pkg_a
  component "pkg_b" as pkg_b
}
pkg_b --> pkg_a
@enduml
'''
            .trim(),
      );
    });
  });
}

void _writePubspec(Directory dir, String content) {
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(content);
}
