import '../component/component_models.dart';
import '../model/api_models.dart';

class ArchitectureNarrative {
  final String narrativeMarkdown;
  final String risksMarkdown;
  final NarrativeHealth health;

  ArchitectureNarrative({
    required this.narrativeMarkdown,
    required this.risksMarkdown,
    required this.health,
  });
}

class NarrativeHealth {
  final int riskCount;
  final int observationCount;
  final int warningCount;

  NarrativeHealth({
    required this.riskCount,
    required this.observationCount,
    required this.warningCount,
  });
}

class ArchitectureRiskReport {
  final List<Component> componentsWithUnknownResponsibility;
  final List<PackageApi> packagesWithApiWarnings;
  final List<Component> componentsWithoutDependents;
  final List<Component> componentsWithoutDependencies;
  final List<PackageApi> packagesWithInternalPublicDeclarations;

  ArchitectureRiskReport({
    required this.componentsWithUnknownResponsibility,
    required this.packagesWithApiWarnings,
    required this.componentsWithoutDependents,
    required this.componentsWithoutDependencies,
    required this.packagesWithInternalPublicDeclarations,
  });

  int get riskCount =>
      componentsWithUnknownResponsibility.length +
      packagesWithApiWarnings.length;

  int get observationCount =>
      componentsWithoutDependents.length +
      componentsWithoutDependencies.length +
      packagesWithInternalPublicDeclarations.length;

  int get warningCount =>
      packagesWithApiWarnings.fold<int>(
        0,
        (sum, api) => sum + api.warnings.length,
      ) +
      componentsWithUnknownResponsibility.length;
}
