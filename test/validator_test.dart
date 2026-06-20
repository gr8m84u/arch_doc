import 'package:test/test.dart';
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('ArchConfig', () {
    test('parses YAML correctly', () {
      final yaml = '''
layers:
  core:
    packages: [pkg1, pkg2]
  impl:
    packages: [pkg3]
rules:
  - name: r1
    from_layer: core
    forbidden_layers: [impl]
ignored_packages: [ignored]
''';
      final config = ArchConfig.fromYaml(yaml);
      expect(config.layers['core'], containsAll(['pkg1', 'pkg2']));
      expect(config.rules[0].name, 'r1');
      expect(config.ignoredPackages, contains('ignored'));
      expect(config.excludedPackages, contains('ignored'));
      expect(config.apiRules.requirePublicEntrypoint, isTrue);
      expect(config.apiRules.forbidExportsFromSrc, isFalse);
      expect(config.componentRules.warnWithoutDependents, isTrue);
      expect(config.riskRules.failOnRisks, isFalse);
      expect(config.output.root, 'doc/arch_doc');
      expect(config.output.workspaceGraph, 'data/workspace_graph.json');
      expect(config.output.packagesDiagramPlantUml, 'diagrams/packages.puml');
      expect(
        config.output.componentsDiagramPlantUml,
        'diagrams/components.puml',
      );
      expect(config.output.remediationGuide, 'remediation.md');
      expect(config.output.contractsReport, 'contracts.md');
      expect(config.output.contractsDiagramPlantUml, 'contracts.puml');
      expect(config.workspaceDiscovery.includeExternalPathPackages, isFalse);
      expect(config.workspaceDiscovery.maxExternalDepth, 2);
      expect(config.contractAnalysis.warnWithoutConsumers, isFalse);
      expect(config.diagramEmbedding.inlineMermaid, isTrue);
      expect(config.contractDiagrams.lldGranularity, 'per_contract');
      expect(config.contractDiagrams.includeComponentLldOverview, isFalse);
    });

    test('parses architecture rules v2 sections', () {
      final yaml = '''
layers: {}
rules: []
api_rules:
  require_public_entrypoint: false
  forbid_exports_from_src: true
  warn_internal_public_declarations: false
  max_exported_symbols_per_package: 10
component_rules:
  require_known_responsibility: false
  warn_without_public_api: false
  warn_without_dependents: false
  warn_without_dependencies: false
risk_rules:
  fail_on_risks: true
  fail_on_warnings: true
  fail_on_observations: true
output:
  root: custom/doc
  readme: index.md
  workspace_graph: graph.json
  packages_diagram: packages.mmd
  packages_diagram_puml: packages.puml
  components_report: components.md
  components_diagram: components.mmd
  components_diagram_puml: components.puml
  narrative_report: narrative.md
  risks_report: risks.md
  remediation_guide: fix.md
  contracts_report: contracts-index.md
  contracts_diagram: contracts-graph.mmd
  contracts_diagram_puml: contracts-graph.puml
  component_contracts_dir: component-contracts
  api_dir: public_api
workspace_discovery:
  include_external_path_packages: true
  max_external_depth: 4
  external_package_labels:
    ../external/pkg: vendor/pkg
excluded_packages: [generated_pkg]
excluded_paths:
  - "**/tmp/**"
contract_analysis:
  enabled: false
  detect_protocols: false
  include_lld_methods: false
  unwrap_async_types: false
  max_methods_per_contract: 7
  warn_without_consumers: true
diagram_embedding:
  mode: link_only
''';
      final config = ArchConfig.fromYaml(yaml);

      expect(config.apiRules.requirePublicEntrypoint, isFalse);
      expect(config.apiRules.forbidExportsFromSrc, isTrue);
      expect(config.apiRules.warnInternalPublicDeclarations, isFalse);
      expect(config.apiRules.maxExportedSymbolsPerPackage, 10);
      expect(config.componentRules.requireKnownResponsibility, isFalse);
      expect(config.componentRules.warnWithoutPublicApi, isFalse);
      expect(config.componentRules.warnWithoutDependents, isFalse);
      expect(config.componentRules.warnWithoutDependencies, isFalse);
      expect(config.riskRules.failOnRisks, isTrue);
      expect(config.riskRules.failOnWarnings, isTrue);
      expect(config.riskRules.failOnObservations, isTrue);
      expect(config.output.root, 'custom/doc');
      expect(config.output.readme, 'index.md');
      expect(config.output.workspaceGraph, 'graph.json');
      expect(config.output.packagesDiagramPlantUml, 'packages.puml');
      expect(config.output.componentsDiagramPlantUml, 'components.puml');
      expect(config.output.apiDir, 'public_api');
      expect(config.output.remediationGuide, 'fix.md');
      expect(config.output.contractsReport, 'contracts-index.md');
      expect(config.output.contractsDiagram, 'contracts-graph.mmd');
      expect(config.output.contractsDiagramPlantUml, 'contracts-graph.puml');
      expect(config.output.componentContractsDir, 'component-contracts');
      expect(config.workspaceDiscovery.includeExternalPathPackages, isTrue);
      expect(config.workspaceDiscovery.maxExternalDepth, 4);
      expect(
        config.workspaceDiscovery.externalPackageLabels['../external/pkg'],
        'vendor/pkg',
      );
      expect(config.excludedPackages, ['generated_pkg']);
      expect(config.excludedPaths, ['**/tmp/**']);
      expect(config.contractAnalysis.enabled, isFalse);
      expect(config.contractAnalysis.detectProtocols, isFalse);
      expect(config.contractAnalysis.includeLldMethods, isFalse);
      expect(config.contractAnalysis.unwrapAsyncTypes, isFalse);
      expect(config.contractAnalysis.maxMethodsPerContract, 7);
      expect(config.contractAnalysis.warnWithoutConsumers, isTrue);
      expect(config.diagramEmbedding.mode, 'link_only');
      expect(config.contractDiagrams.layout, 'layered');
      expect(config.contractDiagrams.view, 'type');
    });

    test('parses contract diagram settings', () {
      final yaml = '''
layers: {}
rules: []
contract_diagrams:
  layout: auto
  view: component
  lld_granularity: component
  include_component_lld_overview: true
''';
      final config = ArchConfig.fromYaml(yaml);

      expect(config.contractDiagrams.layout, 'auto');
      expect(config.contractDiagrams.view, 'component');
      expect(config.contractDiagrams.lldGranularity, 'component');
      expect(config.contractDiagrams.includeComponentLldOverview, isTrue);
    });
  });

  group('ArchValidator', () {
    final nodes = [
      PackageNode(
        name: 'core_pkg',
        path: 'p1',
        description: 'd1',
        declaredDependencies: ['impl_pkg'],
        usedDependencies: ['impl_pkg'],
      ),
      PackageNode(
        name: 'impl_pkg',
        path: 'p2',
        description: 'd2',
        declaredDependencies: [],
        usedDependencies: [],
      ),
      PackageNode(
        name: 'unassigned_pkg',
        path: 'p3',
        description: 'd3',
        declaredDependencies: [],
        usedDependencies: [],
      ),
    ];

    test('detects forbidden layer violation', () {
      final config = ArchConfig(
        layers: {
          'core': ['core_pkg'],
          'impl': ['impl_pkg'],
        },
        rules: [
          ArchRule(
            name: 'no_core_to_impl',
            fromLayer: 'core',
            forbiddenLayers: ['impl'],
          ),
        ],
      );

      final validator = ArchValidator(
        config: config,
        nodes: nodes,
        dependencySource: DependencySource.used,
      );
      final violations = validator.validate();

      final violation = violations.firstWhere(
        (v) => v.ruleName == 'no_core_to_impl',
      );
      expect(violation.packageName, 'core_pkg');
      expect(violation.dependencyName, 'impl_pkg');
      expect(violation.level, ViolationLevel.error);
    });

    test('reports warning for unassigned package', () {
      final config = ArchConfig(
        layers: {
          'core': ['core_pkg'],
          'impl': ['impl_pkg'],
        },
        rules: [],
      );

      final validator = ArchValidator(config: config, nodes: nodes);
      final violations = validator.validate();

      final warning = violations.firstWhere(
        (v) =>
            v.ruleName == 'unassigned_package' &&
            v.packageName == 'unassigned_pkg',
      );
      expect(warning.level, ViolationLevel.warning);
    });

    test('ignores packages in ignored_packages', () {
      final config = ArchConfig(
        layers: {
          'core': ['core_pkg'],
        },
        rules: [],
        ignoredPackages: ['impl_pkg', 'unassigned_pkg'],
      );

      final validator = ArchValidator(config: config, nodes: nodes);
      final violations = validator.validate();

      expect(violations.any((v) => v.packageName == 'impl_pkg'), isFalse);
      expect(violations.any((v) => v.packageName == 'unassigned_pkg'), isFalse);
    });

    test('reports error for non-existent package in config', () {
      final config = ArchConfig(
        layers: {
          'core': ['core_pkg', 'non_existent'],
        },
        rules: [],
      );

      final validator = ArchValidator(config: config, nodes: nodes);
      final violations = validator.validate();

      final error = violations.firstWhere(
        (v) => v.ruleName == 'config_error' && v.packageName == 'non_existent',
      );
      expect(error.level, ViolationLevel.error);
    });
  });
}
