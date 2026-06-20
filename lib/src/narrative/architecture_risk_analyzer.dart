import '../component/component_discovery.dart';
import '../component/component_models.dart';
import '../model/api_models.dart';
import 'architecture_narrative.dart';

class ArchitectureRiskAnalyzer {
  ArchitectureRiskReport analyze(
    ComponentGraph componentGraph,
    Map<String, PackageApi> packageApis,
  ) {
    final components = componentGraph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final apis = packageApis.values.toList()
      ..sort((a, b) => a.packageName.compareTo(b.packageName));

    return ArchitectureRiskReport(
      componentsWithUnknownResponsibility: components
          .where(
            (component) =>
                component.responsibility ==
                ResponsibilityExtractor.unknownResponsibility,
          )
          .toList(),
      packagesWithApiWarnings:
          apis.where((api) => api.warnings.isNotEmpty).toList(),
      componentsWithoutDependents: components
          .where((component) => component.dependents.isEmpty)
          .toList(),
      componentsWithoutDependencies: components
          .where((component) => component.dependencies.isEmpty)
          .toList(),
      packagesWithInternalPublicDeclarations: apis
          .where((api) => api.internalPublicDeclarations.isNotEmpty)
          .toList(),
    );
  }
}
