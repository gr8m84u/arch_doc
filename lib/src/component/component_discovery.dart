import '../model/api_models.dart';
import '../workspace/workspace_graph.dart';
import 'component_models.dart';

class ComponentDiscovery {
  final ResponsibilityExtractor responsibilityExtractor;

  ComponentDiscovery({ResponsibilityExtractor? responsibilityExtractor})
      : responsibilityExtractor =
            responsibilityExtractor ?? ResponsibilityExtractor();

  ComponentGraph discover(
    List<PackageNode> nodes,
    Map<String, PackageApi> packageApis,
  ) {
    final knownPackages = nodes.map((node) => node.name).toSet();
    final dependenciesByPackage = <String, List<String>>{};

    for (final node in nodes) {
      final dependencies = node.usedDependencies
          .where(knownPackages.contains)
          .where((dependency) => dependency != node.name)
          .toSet()
          .toList()
        ..sort();
      dependenciesByPackage[node.name] = dependencies;
    }

    final dependentsByPackage = <String, List<String>>{
      for (final node in nodes) node.name: <String>[],
    };

    for (final entry in dependenciesByPackage.entries) {
      for (final dependency in entry.value) {
        dependentsByPackage[dependency]?.add(entry.key);
      }
    }

    for (final dependents in dependentsByPackage.values) {
      dependents.sort();
    }

    final components = <Component>[];
    for (final node in nodes) {
      final api = packageApis[node.name];
      final publicSurface = (api?.publicSurface ?? []).toList()
        ..sort(_compareDeclarations);
      final dependencies = dependenciesByPackage[node.name] ?? [];
      final dependents = dependentsByPackage[node.name] ?? [];
      final responsibility = responsibilityExtractor.extract(
        packageName: node.name,
        description: node.description,
        publicSurface: publicSurface,
      );
      final warnings = <String>[];

      if (responsibility == ResponsibilityExtractor.unknownResponsibility) {
        warnings.add('Unknown responsibility');
      }
      if (publicSurface.isEmpty) {
        warnings.add('Component without public API');
      }
      if (dependents.isEmpty) {
        warnings.add('No dependents detected in workspace');
      }
      if (dependencies.isEmpty) {
        warnings.add('No dependencies detected');
      }
      warnings.sort();

      components.add(
        Component(
          name: _componentName(node.name),
          packageName: node.name,
          responsibility: responsibility,
          dependencies: dependencies,
          dependents: dependents,
          exportedSymbolCount: publicSurface.length,
          keyExportedSymbols: publicSurface.take(10).toList(),
          warnings: warnings,
        ),
      );
    }

    components.sort((a, b) => a.name.compareTo(b.name));
    return ComponentGraph(components: components);
  }

  String _componentName(String packageName) {
    final withoutSdk = packageName.startsWith('sdk_')
        ? packageName.substring('sdk_'.length)
        : packageName;
    return withoutSdk
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(_titleToken)
        .join(' ');
  }

  String _titleToken(String token) {
    final upper = {'api', 'ffi', 'jwt', 'sdk'};
    if (token.toLowerCase() == 'grpc') return 'gRPC';
    if (upper.contains(token.toLowerCase())) return token.toUpperCase();
    return token.substring(0, 1).toUpperCase() + token.substring(1);
  }
}

class ResponsibilityExtractor {
  static const unknownResponsibility = 'Unknown responsibility';

  String extract({
    required String packageName,
    required String description,
    required List<ApiDeclaration> publicSurface,
  }) {
    final normalizedPackageName = packageName.toLowerCase();
    if (normalizedPackageName.contains('config')) {
      return 'Configuration management';
    }
    if (normalizedPackageName.contains('models')) {
      return 'Shared domain models';
    }
    if (normalizedPackageName.contains('windows') &&
        normalizedPackageName.contains('ffi')) {
      return 'Windows authentication implementation';
    }
    if (normalizedPackageName.contains('linux') &&
        normalizedPackageName.contains('ffi')) {
      return 'Linux authentication implementation';
    }
    if (normalizedPackageName.contains('jwt')) {
      return 'JWT token handling';
    }
    if (normalizedPackageName.contains('identity')) {
      return 'Identity abstractions';
    }
    if (normalizedPackageName.contains('grpc') ||
        normalizedPackageName.contains('contracts')) {
      return 'gRPC contracts and transport';
    }

    final haystack = [
      description,
      ...publicSurface.map((declaration) => declaration.name),
    ].join(' ').toLowerCase();

    if (haystack.contains('models') ||
        haystack.contains('domain models') ||
        haystack.contains('domain model')) {
      return 'Shared domain models';
    }
    if (haystack.contains('identity')) {
      return 'Identity abstractions';
    }
    if (haystack.contains('grpc') || haystack.contains('contract')) {
      return 'gRPC contracts and transport';
    }
    if (haystack.contains('config') || haystack.contains('configuration')) {
      return 'Configuration management';
    }
    if (haystack.contains('authentication')) {
      return 'Authentication services';
    }

    return unknownResponsibility;
  }
}

int _compareDeclarations(ApiDeclaration a, ApiDeclaration b) {
  final kindCompare = a.kind.label.compareTo(b.kind.label);
  if (kindCompare != 0) return kindCompare;
  final nameCompare = a.name.compareTo(b.name);
  if (nameCompare != 0) return nameCompare;
  return a.libraryPath.compareTo(b.libraryPath);
}
