import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('ImportAnalyzer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('import_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('detects package imports correctly', () {
      final file = File(p.join(tempDir.path, 'test.dart'));
      file.writeAsStringSync('''
import 'package:pkg_a/pkg_a.dart';
import "package:pkg_b/src/internal.dart";
export 'package:pkg_c/pkg_c.dart';
part 'package:pkg_d/pkg_d.dart';
import 'dart:async';
import '../local.dart';
''');

      final analyzer = ImportAnalyzer();
      final used = analyzer.analyze(tempDir);

      expect(used, containsAll(['pkg_a', 'pkg_b', 'pkg_c', 'pkg_d']));
      expect(used, isNot(contains('dart:async')));
    });

    test('ignores generated files', () {
      File(
        p.join(tempDir.path, 'normal.dart'),
      ).writeAsStringSync("import 'package:pkg_a/a.dart';");
      File(
        p.join(tempDir.path, 'gen.g.dart'),
      ).writeAsStringSync("import 'package:pkg_b/b.dart';");
      File(
        p.join(tempDir.path, 'gen.freezed.dart'),
      ).writeAsStringSync("import 'package:pkg_c/c.dart';");
      File(
        p.join(tempDir.path, 'gen.config.dart'),
      ).writeAsStringSync("import 'package:pkg_d/d.dart';");

      final genDir = Directory(p.join(tempDir.path, 'generated'))..createSync();
      File(
        p.join(genDir.path, 'any.dart'),
      ).writeAsStringSync("import 'package:pkg_e/e.dart';");

      final analyzer = ImportAnalyzer();
      final used = analyzer.analyze(tempDir);

      expect(used, contains('pkg_a'));
      expect(used, isNot(contains('pkg_b')));
      expect(used, isNot(contains('pkg_c')));
      expect(used, isNot(contains('pkg_d')));
      expect(used, isNot(contains('pkg_e')));
    });
  });

  group('PackageNode Dependency Metrics', () {
    test('calculates unused and missing dependencies', () {
      final node = PackageNode(
        name: 'test_pkg',
        path: 'path',
        description: 'desc',
        declaredDependencies: ['pkg_declared_used', 'pkg_declared_unused'],
        usedDependencies: ['pkg_declared_used', 'pkg_undeclared_used'],
      );

      expect(node.unusedDeclaredDependencies, ['pkg_declared_unused']);
      expect(node.missingDeclaredDependencies, ['pkg_undeclared_used']);
    });
  });
}
