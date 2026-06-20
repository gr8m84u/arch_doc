import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import '../model/api_models.dart';

class ApiAnalyzer {
  PackageApi analyze(
    Directory packageDir,
    String packageName,
    String description,
  ) {
    final libDir = Directory(p.join(packageDir.path, 'lib'));
    if (!libDir.existsSync()) {
      return PackageApi(
        packageName: packageName,
        description: description,
        publicSurface: [],
        internalPublicDeclarations: [],
        warnings: ['Missing lib directory.'],
      );
    }

    final warnings = <String>[];
    final declarationsByLibrary = <String, List<ApiDeclaration>>{};
    final unitsByLibrary = <String, CompilationUnit>{};

    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final fileName = p.basename(entity.path);
      if (_isGenerated(fileName, entity.path)) continue;

      final libraryPath = _libraryPath(libDir, entity);
      try {
        final result = parseString(
          content: entity.readAsStringSync(),
          path: entity.path,
        );
        final unit = result.unit;
        unitsByLibrary[libraryPath] = unit;
        declarationsByLibrary[libraryPath] = _extractDeclarations(
          unit,
          libraryPath,
        );
      } catch (e) {
        warnings.add('Could not parse `$libraryPath`: $e');
      }
    }

    final entrypoint = File(p.join(libDir.path, '$packageName.dart'));
    final allDeclarations =
        declarationsByLibrary.values.expand((e) => e).toList();
    final publicSurface = <ApiDeclaration>[];

    if (entrypoint.existsSync()) {
      final entrypointPath = _libraryPath(libDir, entrypoint);
      publicSurface.addAll(
        _libraryNamespace(
          entrypointPath,
          packageName,
          declarationsByLibrary,
          unitsByLibrary,
          warnings,
          <String>{},
        ),
      );
    } else {
      warnings.add('Missing public entrypoint `lib/$packageName.dart`.');
    }

    final publicKeys = publicSurface.map((e) => e.key).toSet();
    final internalPublicDeclarations =
        allDeclarations.where((e) => !publicKeys.contains(e.key)).toList();

    _sortDeclarations(publicSurface);
    _sortDeclarations(internalPublicDeclarations);
    final sortedWarnings = warnings.toSet().toList()..sort();

    return PackageApi(
      packageName: packageName,
      description: description,
      publicSurface: publicSurface,
      internalPublicDeclarations: internalPublicDeclarations,
      warnings: sortedWarnings,
    );
  }

  List<ApiDeclaration> _libraryNamespace(
    String libraryPath,
    String packageName,
    Map<String, List<ApiDeclaration>> declarationsByLibrary,
    Map<String, CompilationUnit> unitsByLibrary,
    List<String> warnings,
    Set<String> visiting,
  ) {
    if (!visiting.add(libraryPath)) return [];

    final declarations = <String, ApiDeclaration>{
      for (final declaration in declarationsByLibrary[libraryPath] ?? [])
        declaration.key: declaration,
    };

    final unit = unitsByLibrary[libraryPath];
    if (unit != null) {
      for (final directive in unit.directives.whereType<ExportDirective>()) {
        if (directive.configurations.isNotEmpty) {
          warnings.add(
            'Conditional export in `$libraryPath` is not supported.',
          );
          continue;
        }

        final exportedPath = _resolveExportPath(
          libraryPath,
          directive.uri.stringValue,
          packageName,
        );
        if (exportedPath == null) continue;
        if (!unitsByLibrary.containsKey(exportedPath)) {
          warnings.add(
            'Could not resolve export `$exportedPath` from `$libraryPath`.',
          );
          continue;
        }

        final exportedDeclarations = _libraryNamespace(
          exportedPath,
          packageName,
          declarationsByLibrary,
          unitsByLibrary,
          warnings,
          visiting,
        );
        for (final declaration in _applyCombinators(
          exportedDeclarations,
          directive.combinators,
        )) {
          declarations[declaration.key] = declaration;
        }
      }
    }

    visiting.remove(libraryPath);
    return declarations.values.toList();
  }

  List<ApiDeclaration> _extractDeclarations(
    CompilationUnit unit,
    String libraryPath,
  ) {
    final declarations = <ApiDeclaration>[];
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        final name = declaration.name.lexeme;
        if (!name.startsWith('_')) {
          declarations.add(
            ApiDeclaration(
              name: name,
              kind: ApiDeclarationKind.classDeclaration,
              libraryPath: libraryPath,
              isAbstract: declaration.abstractKeyword != null,
            ),
          );
        }
      } else if (declaration is EnumDeclaration) {
        final name = declaration.name.lexeme;
        if (!name.startsWith('_')) {
          declarations.add(
            ApiDeclaration(
              name: name,
              kind: ApiDeclarationKind.enumDeclaration,
              libraryPath: libraryPath,
            ),
          );
        }
      } else if (declaration is ExtensionDeclaration) {
        final name = declaration.name?.lexeme;
        if (name != null && !name.startsWith('_')) {
          declarations.add(
            ApiDeclaration(
              name: name,
              kind: ApiDeclarationKind.extensionDeclaration,
              libraryPath: libraryPath,
            ),
          );
        }
      } else if (declaration is MixinDeclaration) {
        final name = declaration.name.lexeme;
        if (!name.startsWith('_')) {
          declarations.add(
            ApiDeclaration(
              name: name,
              kind: ApiDeclarationKind.mixinDeclaration,
              libraryPath: libraryPath,
            ),
          );
        }
      } else if (declaration is TypeAlias) {
        final name = declaration.name.lexeme;
        if (!name.startsWith('_')) {
          declarations.add(
            ApiDeclaration(
              name: name,
              kind: ApiDeclarationKind.typedefDeclaration,
              libraryPath: libraryPath,
            ),
          );
        }
      }
    }
    return declarations;
  }

  List<ApiDeclaration> _applyCombinators(
    List<ApiDeclaration> declarations,
    NodeList<Combinator> combinators,
  ) {
    var filtered = declarations;
    for (final combinator in combinators) {
      if (combinator is ShowCombinator) {
        final shown = combinator.shownNames.map((e) => e.name).toSet();
        filtered = filtered.where((e) => shown.contains(e.name)).toList();
      } else if (combinator is HideCombinator) {
        final hidden = combinator.hiddenNames.map((e) => e.name).toSet();
        filtered = filtered.where((e) => !hidden.contains(e.name)).toList();
      }
    }
    return filtered;
  }

  String? _resolveExportPath(
    String fromLibraryPath,
    String? uri,
    String packageName,
  ) {
    if (uri == null) return null;
    if (uri.startsWith('dart:')) return null;

    if (uri.startsWith('package:')) {
      final prefix = 'package:$packageName/';
      if (!uri.startsWith(prefix)) return null;
      return p.posix.normalize(uri.substring(prefix.length));
    }

    final fromDir = p.posix.dirname(fromLibraryPath);
    return p.posix.normalize(p.posix.join(fromDir == '.' ? '' : fromDir, uri));
  }

  String _libraryPath(Directory libDir, File file) {
    return p.relative(file.path, from: libDir.path).replaceAll('\\', '/');
  }

  void _sortDeclarations(List<ApiDeclaration> declarations) {
    declarations.sort((a, b) {
      final kindCompare = a.kind.label.compareTo(b.kind.label);
      if (kindCompare != 0) return kindCompare;
      final nameCompare = a.name.compareTo(b.name);
      if (nameCompare != 0) return nameCompare;
      return a.libraryPath.compareTo(b.libraryPath);
    });
  }

  bool _isGenerated(String fileName, String filePath) {
    if (fileName.endsWith('.g.dart') ||
        fileName.endsWith('.freezed.dart') ||
        fileName.endsWith('.config.dart')) {
      return true;
    }
    final normalizedPath = filePath.replaceAll('\\', '/');
    if (normalizedPath.contains('/generated/')) {
      return true;
    }
    return false;
  }
}
