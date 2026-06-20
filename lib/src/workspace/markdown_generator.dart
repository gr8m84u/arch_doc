import '../config/arch_config.dart';
import '../model/api_models.dart';
import '../narrative/architecture_narrative.dart';
import '../contract/contract_models.dart';
import '../validation/architecture_violation.dart';
import '../workspace/workspace_graph.dart';

class MarkdownGenerator {
  final List<PackageNode> nodes;
  final ArchConfig config;
  final Map<String, PackageApi> packageApis;
  final NarrativeHealth? narrativeHealth;
  final List<ArchitectureViolation> findings;
  final ComponentContractGraph? contractGraph;
  final String? packageDiagramMermaid;

  MarkdownGenerator({
    required this.nodes,
    required this.config,
    this.packageApis = const {},
    this.narrativeHealth,
    this.findings = const [],
    this.contractGraph,
    this.packageDiagramMermaid,
  });

  String generate() {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Architecture Overview');
    buffer.writeln();

    _writeArchitectureStatus(buffer);
    _writeRecommendedReadingPath(buffer);
    _writePackageLayers(buffer);
    _writeDependencyHealth(buffer);
    _writePublicApiHealth(buffer);
    _writeArchitectureComponents(buffer);
    _writeComponentContracts(buffer);
    _writeArchitectureNarratives(buffer);
    _writeNarrativeHealth(buffer);
    _writeArchitectureRulesV2(buffer);
    _writeArchitectureEvolution(buffer);
    _writeDependencyDiagram(buffer);
    _writeArchitectureRules(buffer);
    _writeValidationStatus(buffer);
    _writeGeneratedFiles(buffer);

    return buffer.toString();
  }

  void _writeGeneratedFiles(StringBuffer buffer) {
    buffer.writeln('## Generated Artifacts');
    buffer.writeln();
    final localPackageCount = nodes.where((node) => !node.isExternal).length;
    final externalPackageCount = nodes.where((node) => node.isExternal).length;
    buffer.writeln('- Local package count: $localPackageCount');
    buffer.writeln('- External package count: $externalPackageCount');
    buffer.writeln();
    buffer.writeln(
      '- [${_fileLabel(config.output.workspaceGraph)}](${_link(config.output.workspaceGraph)}): Machine-readable dependency graph.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.packagesDiagram)}](${_link(config.output.packagesDiagram)}): Mermaid.js package dependency diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.packagesDiagramPlantUml)}](${_link(config.output.packagesDiagramPlantUml)}): PlantUML package dependency diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsReport)}](${_link(config.output.componentsReport)}): Discovered architecture components and responsibilities.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsDiagram)}](${_link(config.output.componentsDiagram)}): Mermaid component dependency diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsDiagramPlantUml)}](${_link(config.output.componentsDiagramPlantUml)}): PlantUML component dependency diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.narrativeReport)}](${_link(config.output.narrativeReport)}): Generated architecture narrative.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.risksReport)}](${_link(config.output.risksReport)}): Architecture Findings report.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.remediationGuide)}](${_link(config.output.remediationGuide)}): Remediation guide for finding codes.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsReport)}](${_link(config.output.contractsReport)}): Component contract documentation.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsDiagram)}](${_link(config.output.contractsDiagram)}): Mermaid component contract diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsDiagramPlantUml)}](${_link(config.output.contractsDiagramPlantUml)}): PlantUML component contract diagram source.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.apiDir)}/](${_link(config.output.apiDir)}/): Per-package public API summaries.',
    );
    buffer.writeln();
  }

  void _writeArchitectureStatus(StringBuffer buffer) {
    buffer.writeln('## Architecture status');
    buffer.writeln();
    final errors = findings
        .where((finding) => finding.level == ViolationLevel.error)
        .length;
    final warnings = findings
        .where((finding) => finding.level == ViolationLevel.warning)
        .length;
    final observations = findings
        .where((finding) => finding.level == ViolationLevel.observation)
        .length;

    if (errors == 0 && warnings == 0 && observations == 0) {
      buffer.writeln('Architecture status: OK');
      buffer.writeln();
      buffer.writeln(
        'See [${_fileLabel(config.output.remediationGuide)}](${_link(config.output.remediationGuide)}) for the severity model and remediation guidance.',
      );
      buffer.writeln();
      return;
    }

    buffer.writeln('| Severity | Count |');
    buffer.writeln('| --- | ---: |');
    buffer.writeln('| Errors | $errors |');
    buffer.writeln('| Warnings | $warnings |');
    buffer.writeln('| Observations | $observations |');
    buffer.writeln();
    buffer.writeln(
      'See [${_fileLabel(config.output.remediationGuide)}](${_link(config.output.remediationGuide)}) for remediation steps.',
    );
    buffer.writeln();
  }

  void _writeRecommendedReadingPath(StringBuffer buffer) {
    buffer.writeln('## Recommended reading path');
    buffer.writeln();
    buffer.writeln('1. Package overview');
    buffer.writeln('2. Component catalog');
    buffer.writeln('3. Component docs for contracts and implementations');
    buffer.writeln('4. Architecture findings');
    buffer.writeln('5. Remediation guide');
    buffer.writeln();
    buffer.writeln(
      'In SDK/library workspaces, observations about missing dependents or missing dependencies are often expected and do not indicate a failure.',
    );
    buffer.writeln();
  }

  void _writePackageLayers(StringBuffer buffer) {
    buffer.writeln('## Package layers');
    buffer.writeln();

    final layerNames = config.layers.keys.toList();
    final packageMap = {for (var node in nodes) node.name: node};

    for (final layer in layerNames) {
      buffer.writeln('### Layer: $layer');
      buffer.writeln();
      buffer.writeln('| Package | Description | Public API |');
      buffer.writeln('| --- | --- | --- |');

      final packagesInLayer = config.layers[layer] ?? const <String>[];
      for (final pkgName in packagesInLayer) {
        final node = packageMap[pkgName];
        final description = node?.description ?? '*No description provided*';
        buffer.writeln(
          '| `$pkgName` | $description | [View API](${_link('${config.output.apiDir}/$pkgName.md')}) |',
        );
      }
      buffer.writeln();
    }
  }

  void _writeDependencyHealth(StringBuffer buffer) {
    buffer.writeln('## Dependency health');
    buffer.writeln();

    final unused = <String>[];
    final missing = <String>[];
    final noLocalDeps = <String>[];
    final unassigned = <String>[];

    final assignedPackages = config.layers.values.expand((e) => e).toSet();
    final knownPackageNames = nodes.map((n) => n.name).toSet();

    for (final node in nodes) {
      if (config.excludedPackages.contains(node.name)) continue;

      if (node.unusedDeclaredDependencies.isNotEmpty) {
        unused.add(
          '`${node.name}`: ${node.unusedDeclaredDependencies.map((e) => '`$e`').join(', ')}',
        );
      }

      final workspaceMissing = node.missingDeclaredDependencies
          .where((m) => knownPackageNames.contains(m))
          .toList();
      if (workspaceMissing.isNotEmpty) {
        missing.add(
          '`${node.name}`: ${workspaceMissing.map((e) => '`$e`').join(', ')}',
        );
      }

      if (node.declaredDependencies.isEmpty &&
          node.usedDependencies
              .where((u) => knownPackageNames.contains(u))
              .isEmpty) {
        noLocalDeps.add('`${node.name}`');
      }

      if (!assignedPackages.contains(node.name)) {
        unassigned.add('`${node.name}`');
      }
    }

    void writeList(String title, List<String> items) {
      buffer.writeln('### $title');
      if (items.isEmpty) {
        buffer.writeln('None');
      } else {
        items.sort();
        for (final item in items) {
          buffer.writeln('- $item');
        }
      }
      buffer.writeln();
    }

    writeList('Declared but unused dependencies', unused);
    writeList('Used but not declared dependencies', missing);
    writeList('Packages with no local dependencies', noLocalDeps);
    writeList('Packages not assigned to any architecture layer', unassigned);
  }

  void _writePublicApiHealth(StringBuffer buffer) {
    buffer.writeln('## Public API health');
    buffer.writeln();

    if (packageApis.isEmpty) {
      buffer.writeln('No API data available.');
      buffer.writeln();
      return;
    }

    buffer.writeln(
      '| Package | Exported symbols | Internal public declarations | API warnings |',
    );
    buffer.writeln('| --- | ---: | ---: | --- |');

    final sortedNodes = nodes.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final node in sortedNodes) {
      final api = packageApis[node.name];
      if (api == null) continue;

      final warnings = api.warnings.toList()..sort();
      final warningText = warnings.isEmpty
          ? 'None'
          : warnings.map(_escapeTableCell).join('<br/>');
      buffer.writeln(
        '| `${node.name}` | ${api.publicSurface.length} | ${api.internalPublicDeclarations.length} | $warningText |',
      );
    }

    buffer.writeln();
  }

  void _writeDependencyDiagram(StringBuffer buffer) {
    buffer.writeln('## Package dependency diagram');
    buffer.writeln();

    final diagram = packageDiagramMermaid;
    if (config.diagramEmbedding.inlineMermaid && diagram != null) {
      if (diagram.length > 4000) {
        buffer.writeln(
          'Package diagram is available as a standalone artifact because it is too large to embed.',
        );
        buffer.writeln();
        buffer.writeln(
          '- [${_fileLabel(config.output.packagesDiagram)}](${_link(config.output.packagesDiagram)})',
        );
      } else {
        buffer.writeln('```mermaid');
        buffer.writeln(diagram.trim());
        buffer.writeln('```');
      }
    } else {
      buffer.writeln(
        'See [${_fileLabel(config.output.packagesDiagram)}](${_link(config.output.packagesDiagram)}) for the full diagram.',
      );
    }
    buffer.writeln();
  }

  void _writeArchitectureComponents(StringBuffer buffer) {
    buffer.writeln('## Architecture Components');
    buffer.writeln();
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsReport)}](${_link(config.output.componentsReport)}): Discovered architecture components and responsibilities.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsDiagram)}](${_link(config.output.componentsDiagram)}): Mermaid component dependency diagram.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentsDiagramPlantUml)}](${_link(config.output.componentsDiagramPlantUml)}): PlantUML component dependency diagram.',
    );
    buffer.writeln();
  }

  void _writeArchitectureNarratives(StringBuffer buffer) {
    buffer.writeln('## Architecture Narratives');
    buffer.writeln();
    buffer.writeln(
      '- [${_fileLabel(config.output.narrativeReport)}](${_link(config.output.narrativeReport)}): Generated architecture narrative.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.risksReport)}](${_link(config.output.risksReport)}): Architecture Findings report.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.remediationGuide)}](${_link(config.output.remediationGuide)}): Finding codes and remediation guide.',
    );
    buffer.writeln();
  }

  void _writeComponentContracts(StringBuffer buffer) {
    buffer.writeln('## Component Contracts');
    buffer.writeln();
    buffer.writeln(
      'Per-component contract documentation contains separate HLD and LLD views. HLD diagrams show package-level relationships; LLD diagrams show interfaces, implementation classes, and direct request/response models.',
    );
    buffer.writeln();
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsReport)}](${_link(config.output.contractsReport)}): Global contract catalog.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsDiagram)}](${_link(config.output.contractsDiagram)}): Mermaid global contract diagram.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.contractsDiagramPlantUml)}](${_link(config.output.contractsDiagramPlantUml)}): PlantUML global contract diagram.',
    );
    buffer.writeln(
      '- [${_fileLabel(config.output.componentContractsDir)}/](${_link(config.output.componentContractsDir)}/): Per-component contract documentation with Mermaid and PlantUML HLD/LLD diagrams.',
    );
    buffer.writeln();

    final contracts = contractGraph;
    if (contracts == null) {
      buffer.writeln('No contract data available.');
      buffer.writeln();
      return;
    }

    final behaviorContracts = contracts.contracts
        .where((contract) => contract.isBehaviorContract)
        .length;
    final supportingDomainTypes = contracts.contracts
        .where((contract) => contract.isSupportingDomainType)
        .length;
    final technicalTypes = contracts.contracts
        .where((contract) => contract.isTechnicalOrGeneratedType)
        .length;
    final concreteTypes = contracts.contracts
        .where((contract) => contract.isContractLikeConcreteClass)
        .length;

    buffer.writeln('| Metric | Count |');
    buffer.writeln('| --- | ---: |');
    buffer.writeln('| Behavior contracts | $behaviorContracts |');
    buffer.writeln('| Supporting/domain types | $supportingDomainTypes |');
    buffer.writeln('| Technical/generated types | $technicalTypes |');
    buffer.writeln('| Contract-like concrete classes | $concreteTypes |');
    buffer.writeln(
      '| Protocol not detected | ${contracts.protocolNotDetectedCount} |',
    );
    buffer.writeln(
      '| Provider not detected | ${contracts.providerNotDetectedCount} |',
    );
    buffer.writeln(
      '| Contracts without detected consumers | ${contracts.notDetectedInWorkspaceConsumerCount} |',
    );
    buffer.writeln(
      '| Implementation warnings | ${contracts.implementationWarningCount} |',
    );
    buffer.writeln();
  }

  void _writeNarrativeHealth(StringBuffer buffer) {
    buffer.writeln('## Narrative health');
    buffer.writeln();
    final health = narrativeHealth;
    if (health == null) {
      buffer.writeln('No narrative health data available.');
      buffer.writeln();
      return;
    }
    buffer.writeln('| Risks | Observations | Warnings |');
    buffer.writeln('| ---: | ---: | ---: |');
    buffer.writeln(
      '| ${health.riskCount} | ${health.observationCount} | ${health.warningCount} |',
    );
    buffer.writeln();
  }

  void _writeArchitectureRulesV2(StringBuffer buffer) {
    buffer.writeln('## Architecture Rules v2');
    buffer.writeln();
    buffer.writeln('Severity model:');
    buffer.writeln();
    buffer.writeln('- `error`: fails `validate` with exit code 1.');
    buffer.writeln(
      '- `warning`: reported by `validate`, but does not fail by default.',
    );
    buffer.writeln(
      '- `observation`: neutral architecture fact reported by `validate`, but does not fail by default.',
    );
    buffer.writeln();

    buffer.writeln('### API rules');
    buffer.writeln();
    buffer.writeln('| Rule | Value |');
    buffer.writeln('| --- | --- |');
    buffer.writeln(
      '| `require_public_entrypoint` | `${config.apiRules.requirePublicEntrypoint}` |',
    );
    buffer.writeln(
      '| `forbid_exports_from_src` | `${config.apiRules.forbidExportsFromSrc}` |',
    );
    buffer.writeln(
      '| `warn_internal_public_declarations` | `${config.apiRules.warnInternalPublicDeclarations}` |',
    );
    buffer.writeln(
      '| `max_exported_symbols_per_package` | `${config.apiRules.maxExportedSymbolsPerPackage ?? 'null'}` |',
    );
    buffer.writeln();

    buffer.writeln('### Component rules');
    buffer.writeln();
    buffer.writeln('| Rule | Value |');
    buffer.writeln('| --- | --- |');
    buffer.writeln(
      '| `require_known_responsibility` | `${config.componentRules.requireKnownResponsibility}` |',
    );
    buffer.writeln(
      '| `warn_without_public_api` | `${config.componentRules.warnWithoutPublicApi}` |',
    );
    buffer.writeln(
      '| `warn_without_dependents` | `${config.componentRules.warnWithoutDependents}` |',
    );
    buffer.writeln(
      '| `warn_without_dependencies` | `${config.componentRules.warnWithoutDependencies}` |',
    );
    buffer.writeln();

    buffer.writeln('### Risk policy');
    buffer.writeln();
    buffer.writeln('| Rule | Value |');
    buffer.writeln('| --- | --- |');
    buffer.writeln('| `fail_on_risks` | `${config.riskRules.failOnRisks}` |');
    buffer.writeln(
      '| `fail_on_warnings` | `${config.riskRules.failOnWarnings}` |',
    );
    buffer.writeln(
      '| `fail_on_observations` | `${config.riskRules.failOnObservations}` |',
    );
    buffer.writeln();
  }

  void _writeArchitectureEvolution(StringBuffer buffer) {
    buffer.writeln('## Architecture Evolution');
    buffer.writeln();
    buffer.writeln(
      '- **M1 Package-level architecture docs**: workspace graph, package layers, and dependency rules.',
    );
    buffer.writeln(
      '- **M2 Public API summary**: per-package public declaration summaries.',
    );
    buffer.writeln(
      '- **M3 Public Surface Analysis**: exported API detection from package entrypoints.',
    );
    buffer.writeln(
      '- **M4 Component Discovery**: component responsibilities and component dependency diagram.',
    );
    buffer.writeln(
      '- **M5 Architecture Narratives**: generated architecture narrative and risks/observations.',
    );
    buffer.writeln(
      '- **M6 Architecture Rules v2**: API, component, and risk-policy validation.',
    );
    buffer.writeln();
  }

  void _writeArchitectureRules(StringBuffer buffer) {
    buffer.writeln('## Architecture rules');
    buffer.writeln();

    final sortedRules = config.rules.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final rule in sortedRules) {
      buffer.writeln(
        '- **${rule.name}**: Layer `${rule.fromLayer}` cannot depend on:',
      );
      final sortedForbidden = rule.forbiddenLayers.toList()..sort();
      for (final forbidden in sortedForbidden) {
        buffer.writeln('  - `$forbidden`');
      }
    }
    buffer.writeln();
  }

  void _writeValidationStatus(StringBuffer buffer) {
    buffer.writeln('## Validation status');
    buffer.writeln();
    buffer.writeln(
      'This document is automatically generated. To ensure the workspace adheres to these rules, run:',
    );
    buffer.writeln();
    buffer.writeln('```powershell');
    buffer.writeln(r'dart run bin\arch_doc.dart validate');
    buffer.writeln('```');
    buffer.writeln();
  }

  String _escapeTableCell(String value) {
    return value.replaceAll('|', r'\|');
  }

  String _link(String path) {
    return './${path.replaceAll('\\', '/')}';
  }

  String _fileLabel(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }
}
