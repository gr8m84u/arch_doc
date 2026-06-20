import 'dart:io';
import 'package:yaml/yaml.dart';
import 'arch_rule.dart';

class ArchConfig {
  final Map<String, List<String>> layers;
  final List<ArchRule> rules;
  final List<String> excludedPackages;
  final List<String> excludedPaths;
  final ApiRulesConfig apiRules;
  final ComponentRulesConfig componentRules;
  final RiskRulesConfig riskRules;
  final OutputConfig output;
  final WorkspaceDiscoveryConfig workspaceDiscovery;
  final ContractAnalysisConfig contractAnalysis;
  final DiagramEmbeddingConfig diagramEmbedding;
  final ContractDiagramsConfig contractDiagrams;

  ArchConfig({
    required this.layers,
    required this.rules,
    List<String> ignoredPackages = const [],
    List<String>? excludedPackages,
    List<String>? excludedPaths,
    ApiRulesConfig? apiRules,
    ComponentRulesConfig? componentRules,
    RiskRulesConfig? riskRules,
    OutputConfig? output,
    WorkspaceDiscoveryConfig? workspaceDiscovery,
    ContractAnalysisConfig? contractAnalysis,
    DiagramEmbeddingConfig? diagramEmbedding,
    ContractDiagramsConfig? contractDiagrams,
  })  : excludedPackages = excludedPackages ?? ignoredPackages,
        excludedPaths =
            excludedPaths ?? WorkspaceDiscoveryConfig.defaultExcludedPaths,
        apiRules = apiRules ?? ApiRulesConfig.defaults(),
        componentRules = componentRules ?? ComponentRulesConfig.defaults(),
        riskRules = riskRules ?? RiskRulesConfig.defaults(),
        output = output ?? OutputConfig.defaults(),
        workspaceDiscovery =
            workspaceDiscovery ?? WorkspaceDiscoveryConfig.defaults(),
        contractAnalysis =
            contractAnalysis ?? ContractAnalysisConfig.defaults(),
        diagramEmbedding =
            diagramEmbedding ?? DiagramEmbeddingConfig.defaults(),
        contractDiagrams =
            contractDiagrams ?? ContractDiagramsConfig.defaults();

  List<String> get ignoredPackages => excludedPackages;

  factory ArchConfig.fromYaml(String yamlContent) {
    final yaml = loadYaml(yamlContent) as YamlMap;

    final layersMap = <String, List<String>>{};
    final layersYaml = yaml['layers'] as YamlMap?;
    if (layersYaml != null) {
      layersYaml.forEach((key, value) {
        if (value is YamlMap && value.containsKey('packages')) {
          final pkgs = value['packages'] as YamlList?;
          if (pkgs != null) {
            layersMap[key as String] = pkgs.cast<String>().toList();
          }
        }
      });
    }

    final rulesList = <ArchRule>[];
    final rulesYaml = yaml['rules'] as YamlList?;
    if (rulesYaml != null) {
      for (final ruleYaml in rulesYaml) {
        if (ruleYaml is YamlMap) {
          rulesList.add(
            ArchRule(
              name: ruleYaml['name'] as String,
              fromLayer: ruleYaml['from_layer'] as String,
              forbiddenLayers: (ruleYaml['forbidden_layers'] as YamlList)
                  .cast<String>()
                  .toList(),
            ),
          );
        }
      }
    }

    final ignored = <String>[];
    final ignoredYaml = yaml['ignored_packages'] as YamlList?;
    if (ignoredYaml != null) {
      ignored.addAll(ignoredYaml.cast<String>());
    }
    final excluded = <String>[];
    final excludedYaml = yaml['excluded_packages'] as YamlList?;
    if (excludedYaml != null) {
      excluded.addAll(excludedYaml.cast<String>());
    }
    final excludedPaths = <String>[];
    final excludedPathsYaml = yaml['excluded_paths'] as YamlList?;
    if (excludedPathsYaml != null) {
      excludedPaths.addAll(excludedPathsYaml.cast<String>());
    }

    return ArchConfig(
      layers: layersMap,
      rules: rulesList,
      excludedPackages: [
        ...ignored,
        ...excluded.where((pkg) => !ignored.contains(pkg)),
      ],
      excludedPaths: excludedPaths.isEmpty
          ? WorkspaceDiscoveryConfig.defaultExcludedPaths
          : excludedPaths,
      apiRules: ApiRulesConfig.fromYaml(yaml['api_rules'] as YamlMap?),
      componentRules: ComponentRulesConfig.fromYaml(
        yaml['component_rules'] as YamlMap?,
      ),
      riskRules: RiskRulesConfig.fromYaml(yaml['risk_rules'] as YamlMap?),
      output: OutputConfig.fromYaml(yaml['output'] as YamlMap?),
      workspaceDiscovery: WorkspaceDiscoveryConfig.fromYaml(
        yaml['workspace_discovery'] as YamlMap?,
      ),
      contractAnalysis: ContractAnalysisConfig.fromYaml(
        yaml['contract_analysis'] as YamlMap?,
      ),
      diagramEmbedding: DiagramEmbeddingConfig.fromYaml(
        yaml['diagram_embedding'] as YamlMap?,
      ),
      contractDiagrams: ContractDiagramsConfig.fromYaml(
        yaml['contract_diagrams'] as YamlMap?,
      ),
    );
  }

  static ArchConfig load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Configuration file not found', path);
    }
    return ArchConfig.fromYaml(file.readAsStringSync());
  }
}

class ContractAnalysisConfig {
  final bool enabled;
  final bool detectProtocols;
  final bool includeLldMethods;
  final bool unwrapAsyncTypes;
  final int maxMethodsPerContract;
  final bool warnWithoutConsumers;
  final bool includeGeneratedMethods;

  ContractAnalysisConfig({
    required this.enabled,
    required this.detectProtocols,
    required this.includeLldMethods,
    required this.unwrapAsyncTypes,
    required this.maxMethodsPerContract,
    required this.warnWithoutConsumers,
    required this.includeGeneratedMethods,
  });

  factory ContractAnalysisConfig.defaults() {
    return ContractAnalysisConfig(
      enabled: true,
      detectProtocols: true,
      includeLldMethods: true,
      unwrapAsyncTypes: true,
      maxMethodsPerContract: 50,
      warnWithoutConsumers: false,
      includeGeneratedMethods: false,
    );
  }

  factory ContractAnalysisConfig.fromYaml(YamlMap? yaml) {
    final defaults = ContractAnalysisConfig.defaults();
    if (yaml == null) return defaults;
    return ContractAnalysisConfig(
      enabled: yaml['enabled'] as bool? ?? defaults.enabled,
      detectProtocols:
          yaml['detect_protocols'] as bool? ?? defaults.detectProtocols,
      includeLldMethods:
          yaml['include_lld_methods'] as bool? ?? defaults.includeLldMethods,
      unwrapAsyncTypes:
          yaml['unwrap_async_types'] as bool? ?? defaults.unwrapAsyncTypes,
      maxMethodsPerContract: yaml['max_methods_per_contract'] as int? ??
          defaults.maxMethodsPerContract,
      warnWithoutConsumers: yaml['warn_without_consumers'] as bool? ??
          defaults.warnWithoutConsumers,
      includeGeneratedMethods: yaml['include_generated_methods'] as bool? ??
          defaults.includeGeneratedMethods,
    );
  }
}

class DiagramEmbeddingConfig {
  final String mode;

  DiagramEmbeddingConfig({required this.mode});

  factory DiagramEmbeddingConfig.defaults() {
    return DiagramEmbeddingConfig(mode: 'inline_mermaid');
  }

  factory DiagramEmbeddingConfig.fromYaml(YamlMap? yaml) {
    final defaults = DiagramEmbeddingConfig.defaults();
    if (yaml == null) return defaults;
    final mode = yaml['mode'] as String? ?? defaults.mode;
    return DiagramEmbeddingConfig(
      mode: mode == 'link_only' ? 'link_only' : 'inline_mermaid',
    );
  }

  bool get inlineMermaid => mode == 'inline_mermaid';
}

class ContractDiagramsConfig {
  final String layout;
  final String view;
  final String lldGranularity;
  final bool includeComponentLldOverview;

  ContractDiagramsConfig({
    required this.layout,
    required this.view,
    this.lldGranularity = 'per_contract',
    this.includeComponentLldOverview = false,
  });

  factory ContractDiagramsConfig.defaults() {
    return ContractDiagramsConfig(
      layout: 'layered',
      view: 'type',
      lldGranularity: 'per_contract',
      includeComponentLldOverview: false,
    );
  }

  factory ContractDiagramsConfig.fromYaml(YamlMap? yaml) {
    final defaults = ContractDiagramsConfig.defaults();
    if (yaml == null) return defaults;
    final layout = yaml['layout'] as String? ?? defaults.layout;
    final view = yaml['view'] as String? ?? defaults.view;
    final lldGranularity =
        yaml['lld_granularity'] as String? ?? defaults.lldGranularity;
    return ContractDiagramsConfig(
      layout: layout == 'auto' ? 'auto' : 'layered',
      view: view == 'component' ? 'component' : 'type',
      lldGranularity:
          lldGranularity == 'component' ? 'component' : 'per_contract',
      includeComponentLldOverview:
          yaml['include_component_lld_overview'] as bool? ??
              defaults.includeComponentLldOverview,
    );
  }

  bool get layered => layout == 'layered';
  bool get componentView => view == 'component';
  bool get perContractLld => lldGranularity == 'per_contract';
}

class WorkspaceDiscoveryConfig {
  static const defaultExcludedPaths = [
    '**/.dart_tool/**',
    '**/build/**',
    '.git',
    'tools/arch_doc',
  ];

  final bool includeExternalPathPackages;
  final int maxExternalDepth;
  final Map<String, String> externalPackageLabels;

  WorkspaceDiscoveryConfig({
    required this.includeExternalPathPackages,
    required this.maxExternalDepth,
    required this.externalPackageLabels,
  });

  factory WorkspaceDiscoveryConfig.defaults() {
    return WorkspaceDiscoveryConfig(
      includeExternalPathPackages: false,
      maxExternalDepth: 2,
      externalPackageLabels: const {},
    );
  }

  factory WorkspaceDiscoveryConfig.fromYaml(YamlMap? yaml) {
    final defaults = WorkspaceDiscoveryConfig.defaults();
    if (yaml == null) return defaults;

    final labels = <String, String>{};
    final labelsYaml = yaml['external_package_labels'] as YamlMap?;
    if (labelsYaml != null) {
      labelsYaml.forEach((key, value) {
        if (key is String && value is String) {
          labels[key] = value;
        }
      });
    }

    return WorkspaceDiscoveryConfig(
      includeExternalPathPackages:
          yaml['include_external_path_packages'] as bool? ??
              defaults.includeExternalPathPackages,
      maxExternalDepth:
          yaml['max_external_depth'] as int? ?? defaults.maxExternalDepth,
      externalPackageLabels: labels,
    );
  }
}

class OutputConfig {
  final String root;
  final String readme;
  final String workspaceGraph;
  final String packagesDiagram;
  final String packagesDiagramPlantUml;
  final String componentsReport;
  final String componentsDiagram;
  final String componentsDiagramPlantUml;
  final String narrativeReport;
  final String risksReport;
  final String remediationGuide;
  final String contractsReport;
  final String contractsDiagram;
  final String contractsDiagramPlantUml;
  final String componentContractsDir;
  final String apiDir;

  OutputConfig({
    required this.root,
    required this.readme,
    required this.workspaceGraph,
    required this.packagesDiagram,
    required this.packagesDiagramPlantUml,
    required this.componentsReport,
    required this.componentsDiagram,
    required this.componentsDiagramPlantUml,
    required this.narrativeReport,
    required this.risksReport,
    required this.remediationGuide,
    required this.contractsReport,
    required this.contractsDiagram,
    required this.contractsDiagramPlantUml,
    required this.componentContractsDir,
    required this.apiDir,
  });

  factory OutputConfig.defaults() {
    return OutputConfig(
      root: 'doc/arch_doc',
      readme: 'README.md',
      workspaceGraph: 'data/workspace_graph.json',
      packagesDiagram: 'diagrams/packages.mmd',
      packagesDiagramPlantUml: 'diagrams/packages.puml',
      componentsReport: 'reports/components.md',
      componentsDiagram: 'diagrams/components.mmd',
      componentsDiagramPlantUml: 'diagrams/components.puml',
      narrativeReport: 'reports/narrative.md',
      risksReport: 'reports/risks.md',
      remediationGuide: 'remediation.md',
      contractsReport: 'contracts.md',
      contractsDiagram: 'contracts.mmd',
      contractsDiagramPlantUml: 'contracts.puml',
      componentContractsDir: 'components',
      apiDir: 'api',
    );
  }

  factory OutputConfig.fromYaml(YamlMap? yaml) {
    final defaults = OutputConfig.defaults();
    if (yaml == null) return defaults;
    return OutputConfig(
      root: yaml['root'] as String? ?? defaults.root,
      readme: yaml['readme'] as String? ?? defaults.readme,
      workspaceGraph:
          yaml['workspace_graph'] as String? ?? defaults.workspaceGraph,
      packagesDiagram:
          yaml['packages_diagram'] as String? ?? defaults.packagesDiagram,
      packagesDiagramPlantUml: yaml['packages_diagram_puml'] as String? ??
          defaults.packagesDiagramPlantUml,
      componentsReport:
          yaml['components_report'] as String? ?? defaults.componentsReport,
      componentsDiagram:
          yaml['components_diagram'] as String? ?? defaults.componentsDiagram,
      componentsDiagramPlantUml: yaml['components_diagram_puml'] as String? ??
          defaults.componentsDiagramPlantUml,
      narrativeReport:
          yaml['narrative_report'] as String? ?? defaults.narrativeReport,
      risksReport: yaml['risks_report'] as String? ?? defaults.risksReport,
      remediationGuide:
          yaml['remediation_guide'] as String? ?? defaults.remediationGuide,
      contractsReport:
          yaml['contracts_report'] as String? ?? defaults.contractsReport,
      contractsDiagram:
          yaml['contracts_diagram'] as String? ?? defaults.contractsDiagram,
      contractsDiagramPlantUml: yaml['contracts_diagram_puml'] as String? ??
          defaults.contractsDiagramPlantUml,
      componentContractsDir: yaml['component_contracts_dir'] as String? ??
          defaults.componentContractsDir,
      apiDir: yaml['api_dir'] as String? ?? defaults.apiDir,
    );
  }
}

class ApiRulesConfig {
  final bool requirePublicEntrypoint;
  final bool forbidExportsFromSrc;
  final bool warnInternalPublicDeclarations;
  final int? maxExportedSymbolsPerPackage;

  ApiRulesConfig({
    required this.requirePublicEntrypoint,
    required this.forbidExportsFromSrc,
    required this.warnInternalPublicDeclarations,
    required this.maxExportedSymbolsPerPackage,
  });

  factory ApiRulesConfig.defaults() {
    return ApiRulesConfig(
      requirePublicEntrypoint: true,
      forbidExportsFromSrc: false,
      warnInternalPublicDeclarations: true,
      maxExportedSymbolsPerPackage: null,
    );
  }

  factory ApiRulesConfig.fromYaml(YamlMap? yaml) {
    final defaults = ApiRulesConfig.defaults();
    if (yaml == null) return defaults;
    return ApiRulesConfig(
      requirePublicEntrypoint: yaml['require_public_entrypoint'] as bool? ??
          defaults.requirePublicEntrypoint,
      forbidExportsFromSrc: yaml['forbid_exports_from_src'] as bool? ??
          defaults.forbidExportsFromSrc,
      warnInternalPublicDeclarations:
          yaml['warn_internal_public_declarations'] as bool? ??
              defaults.warnInternalPublicDeclarations,
      maxExportedSymbolsPerPackage:
          yaml['max_exported_symbols_per_package'] as int?,
    );
  }
}

class ComponentRulesConfig {
  final bool requireKnownResponsibility;
  final bool warnWithoutPublicApi;
  final bool warnWithoutDependents;
  final bool warnWithoutDependencies;

  ComponentRulesConfig({
    required this.requireKnownResponsibility,
    required this.warnWithoutPublicApi,
    required this.warnWithoutDependents,
    required this.warnWithoutDependencies,
  });

  factory ComponentRulesConfig.defaults() {
    return ComponentRulesConfig(
      requireKnownResponsibility: true,
      warnWithoutPublicApi: true,
      warnWithoutDependents: true,
      warnWithoutDependencies: true,
    );
  }

  factory ComponentRulesConfig.fromYaml(YamlMap? yaml) {
    final defaults = ComponentRulesConfig.defaults();
    if (yaml == null) return defaults;
    return ComponentRulesConfig(
      requireKnownResponsibility:
          yaml['require_known_responsibility'] as bool? ??
              defaults.requireKnownResponsibility,
      warnWithoutPublicApi: yaml['warn_without_public_api'] as bool? ??
          defaults.warnWithoutPublicApi,
      warnWithoutDependents: yaml['warn_without_dependents'] as bool? ??
          defaults.warnWithoutDependents,
      warnWithoutDependencies: yaml['warn_without_dependencies'] as bool? ??
          defaults.warnWithoutDependencies,
    );
  }
}

class RiskRulesConfig {
  final bool failOnRisks;
  final bool failOnWarnings;
  final bool failOnObservations;

  RiskRulesConfig({
    required this.failOnRisks,
    required this.failOnWarnings,
    required this.failOnObservations,
  });

  factory RiskRulesConfig.defaults() {
    return RiskRulesConfig(
      failOnRisks: false,
      failOnWarnings: false,
      failOnObservations: false,
    );
  }

  factory RiskRulesConfig.fromYaml(YamlMap? yaml) {
    final defaults = RiskRulesConfig.defaults();
    if (yaml == null) return defaults;
    return RiskRulesConfig(
      failOnRisks: yaml['fail_on_risks'] as bool? ?? defaults.failOnRisks,
      failOnWarnings:
          yaml['fail_on_warnings'] as bool? ?? defaults.failOnWarnings,
      failOnObservations:
          yaml['fail_on_observations'] as bool? ?? defaults.failOnObservations,
    );
  }
}
