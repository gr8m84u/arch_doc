import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:arch_doc/arch_doc.dart';

void main() {
  late Directory tempDir;

  void _writeLib(String relativePath, String content) {
    final file = File(
      p.joinAll([tempDir.path, 'lib', ...p.split(relativePath)]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  List<String> _names(List<ApiDeclaration> declarations) {
    return declarations.map((e) => e.name).toList();
  }

  group('ApiAnalyzer', () {
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('api_test_');
      Directory(p.join(tempDir.path, 'lib')).createSync();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('extracts public surface from the package entrypoint', () {
      _writeLib('test_pkg.dart', '''
export 'src/api.dart';
class EntrypointClass {}
''');
      _writeLib('src/api.dart', '''
class PublicClass {}
abstract class AbstractClass {}
class _PrivateClass {}

enum PublicEnum { a, b }
enum _PrivateEnum { c }

extension PublicExtension on String {}
extension _PrivateExtension on int {}

mixin PublicMixin {}
mixin _PrivateMixin {}

typedef PublicTypedef = void Function();
typedef _PrivateTypedef = int;
''');
      _writeLib('src/internal.dart', 'class InternalOnly {}');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(
        _names(api.publicSurface),
        containsAll([
          'EntrypointClass',
          'PublicClass',
          'AbstractClass',
          'PublicEnum',
          'PublicExtension',
          'PublicMixin',
          'PublicTypedef',
        ]),
      );
      expect(_names(api.publicSurface), isNot(contains('_PrivateClass')));
      expect(_names(api.internalPublicDeclarations), contains('InternalOnly'));
      expect(
        api.publicSurface.any(
          (e) =>
              e.name == 'AbstractClass' &&
              e.kind == ApiDeclarationKind.classDeclaration &&
              e.libraryPath == 'src/api.dart' &&
              e.isAbstract,
        ),
        isTrue,
      );
    });

    test(
      'classifies all public declarations as internal when entrypoint is missing',
      () {
        _writeLib('src/api.dart', 'class PublicClass {}');

        final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

        expect(api.publicSurface, isEmpty);
        expect(_names(api.internalPublicDeclarations), ['PublicClass']);
        expect(
          api.warnings,
          contains('Missing public entrypoint `lib/test_pkg.dart`.'),
        );
      },
    );

    test('ignores generated files', () {
      _writeLib('test_pkg.dart', "export 'normal.dart';");
      _writeLib('normal.dart', 'class Normal {}');
      _writeLib('gen.g.dart', 'class Generated {}');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), contains('Normal'));
      expect(
        _names(api.internalPublicDeclarations),
        isNot(contains('Generated')),
      );
    });

    test('sorts declarations deterministically', () {
      _writeLib('test_pkg.dart', '''
export 'z.dart';
export 'a.dart';
''');
      _writeLib('z.dart', '''
class Same {}
enum ZEnum { value }
''');
      _writeLib('a.dart', '''
class Same {}
enum AEnum { value }
''');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), ['Same', 'Same', 'AEnum', 'ZEnum']);
      expect(api.publicSurface.map((e) => e.libraryPath), [
        'a.dart',
        'z.dart',
        'a.dart',
        'z.dart',
      ]);
    });

    test('sorts warnings alphabetically and removes duplicates', () {
      _writeLib('test_pkg.dart', '''
export 'z_missing.dart';
export 'a_missing.dart';
export 'z_missing.dart';
''');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(api.warnings, [
        'Could not resolve export `a_missing.dart` from `test_pkg.dart`.',
        'Could not resolve export `z_missing.dart` from `test_pkg.dart`.',
      ]);
    });

    test('handles an empty package entrypoint', () {
      _writeLib('test_pkg.dart', '');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(api.publicSurface, isEmpty);
      expect(api.internalPublicDeclarations, isEmpty);
      expect(api.warnings, isEmpty);
    });

    test('reports a warning for a missing exported file', () {
      _writeLib('test_pkg.dart', "export 'missing.dart';");
      _writeLib('internal.dart', 'class InternalOnly {}');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(api.publicSurface, isEmpty);
      expect(_names(api.internalPublicDeclarations), ['InternalOnly']);
      expect(api.warnings, [
        'Could not resolve export `missing.dart` from `test_pkg.dart`.',
      ]);
    });

    test('handles cyclic re-exports without duplicating declarations', () {
      _writeLib('test_pkg.dart', "export 'a.dart';");
      _writeLib('a.dart', '''
export 'b.dart';
class A {}
''');
      _writeLib('b.dart', '''
export 'a.dart';
class B {}
''');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), ['A', 'B']);
      expect(api.internalPublicDeclarations, isEmpty);
      expect(api.warnings, isEmpty);
    });

    test('deduplicates duplicate exports of the same declaration', () {
      _writeLib('test_pkg.dart', '''
export 'a.dart';
export 'b.dart';
''');
      _writeLib('a.dart', "export 'shared.dart';");
      _writeLib('b.dart', "export 'shared.dart';");
      _writeLib('shared.dart', 'class Shared {}');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), ['Shared']);
      expect(api.publicSurface, hasLength(1));
    });

    test('applies show and hide combinators on direct exports', () {
      _writeLib('test_pkg.dart', '''
export 'shown.dart' show Shown;
export 'hidden.dart' hide Hidden;
''');
      _writeLib('shown.dart', '''
class Shown {}
class NotShown {}
''');
      _writeLib('hidden.dart', '''
class Visible {}
class Hidden {}
''');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), ['Shown', 'Visible']);
      expect(
        _names(api.internalPublicDeclarations),
        containsAll(['Hidden', 'NotShown']),
      );
    });

    test('resolves re-exports with show and hide combinators', () {
      _writeLib('test_pkg.dart', "export 'a.dart';");
      _writeLib('a.dart', '''
export 'b.dart' show Alpha, Beta, Gamma hide Beta;
class FromA {}
''');
      _writeLib('b.dart', '''
class Alpha {}
class Beta {}
class Gamma {}
class Delta {}
''');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(_names(api.publicSurface), ['Alpha', 'FromA', 'Gamma']);
      expect(
        _names(api.internalPublicDeclarations),
        containsAll(['Beta', 'Delta']),
      );
    });

    test('uses declaration identity instead of name alone', () {
      _writeLib('test_pkg.dart', "export 'public.dart';");
      _writeLib('public.dart', 'class Duplicate {}');
      _writeLib('internal.dart', 'enum Duplicate { value }');

      final api = ApiAnalyzer().analyze(tempDir, 'test_pkg', 'desc');

      expect(
        api.publicSurface.singleWhere((e) => e.name == 'Duplicate').kind,
        ApiDeclarationKind.classDeclaration,
      );
      expect(
        api.internalPublicDeclarations
            .singleWhere((e) => e.name == 'Duplicate')
            .kind,
        ApiDeclarationKind.enumDeclaration,
      );
    });
  });

  group('ApiMarkdownGenerator', () {
    test(
      'generates public surface and internal public declaration sections',
      () {
        final api = PackageApi(
          packageName: 'test_pkg',
          description: 'desc',
          publicSurface: [
            ApiDeclaration(
              name: 'PublicClass',
              kind: ApiDeclarationKind.classDeclaration,
              libraryPath: 'src/api.dart',
              isAbstract: true,
            ),
          ],
          internalPublicDeclarations: [
            ApiDeclaration(
              name: 'InternalEnum',
              kind: ApiDeclarationKind.enumDeclaration,
              libraryPath: 'src/internal.dart',
            ),
          ],
          warnings: ['Missing public entrypoint `lib/test_pkg.dart`.'],
        );

        final markdown = ApiMarkdownGenerator(api).generate();

        expect(
          markdown.trim(),
          '''
<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->
# Public API Summary: test_pkg

desc

## Warnings

- Missing public entrypoint `lib/test_pkg.dart`.

## Public Surface

- `PublicClass` (Class, `src/api.dart`) (abstract)

## Internal Public Declarations

- `InternalEnum` (Enum, `src/internal.dart`)

## Known limitations

- Conditional exports not yet supported.
- Methods and comments are not analyzed.
'''
              .trim(),
        );
      },
    );
  });
}
