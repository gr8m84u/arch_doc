import '../model/api_models.dart';

class ComponentGraph {
  final List<Component> components;

  ComponentGraph({required this.components});
}

class Component {
  final String name;
  final String packageName;
  final String responsibility;
  final List<String> dependencies;
  final List<String> dependents;
  final int exportedSymbolCount;
  final List<ApiDeclaration> keyExportedSymbols;
  final List<String> warnings;

  Component({
    required this.name,
    required this.packageName,
    required this.responsibility,
    required this.dependencies,
    required this.dependents,
    required this.exportedSymbolCount,
    required this.keyExportedSymbols,
    this.warnings = const [],
  });
}
