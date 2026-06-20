import 'package:path/path.dart' as p;

import '../component/component_models.dart';
import '../config/arch_config.dart';
import '../model/api_models.dart';
import '../validation/architecture_violation.dart';
import '../workspace/workspace_graph.dart';
import 'architecture_narrative.dart';
import 'architecture_risk_analyzer.dart';

class ArchitectureNarrativeGenerator {
  static const generatorName = 'arch_doc narrative v1';

  final List<PackageNode> packages;
  final ComponentGraph componentGraph;
  final ArchConfig config;
  final Map<String, PackageApi> packageApis;
  final List<ArchitectureViolation> findings;

  ArchitectureNarrativeGenerator({
    required this.packages,
    required this.componentGraph,
    required this.config,
    required this.packageApis,
    this.findings = const [],
  });

  ArchitectureNarrative generate() {
    final report = ArchitectureRiskAnalyzer().analyze(
      componentGraph,
      packageApis,
    );
    final activeFindings = findings.toList()..sort(_compareFindings);
    final health = NarrativeHealth(
      riskCount: activeFindings
          .where((finding) => finding.level == ViolationLevel.error)
          .length,
      observationCount: activeFindings
          .where((finding) => finding.level == ViolationLevel.observation)
          .length,
      warningCount: activeFindings
          .where((finding) => finding.level == ViolationLevel.warning)
          .length,
    );

    return ArchitectureNarrative(
      narrativeMarkdown: _generateNarrative(),
      risksMarkdown: _generateRisks(report, activeFindings),
      health: health,
    );
  }

  String _generateNarrative() {
    final buffer = StringBuffer();
    final sortedPackages = packages.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final sortedLayerNames = config.layers.keys.toList()..sort();
    final components = componentGraph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final componentsByPackage = {
      for (final component in components) component.packageName: component,
    };
    final totalExportedSymbols = packageApis.values.fold<int>(
      0,
      (sum, api) => sum + api.publicSurface.length,
    );

    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Architecture Narrative');
    buffer.writeln();
    buffer.writeln('## System Overview');
    buffer.writeln();
    buffer.writeln(
      'The workspace contains ${sortedPackages.length} packages organized into ${sortedLayerNames.length} architecture layers.',
    );
    buffer.writeln();

    for (final layer in sortedLayerNames) {
      final packagesInLayer = (config.layers[layer] ?? []).toList()..sort();
      buffer.writeln('${_sentenceCase(layer)} layer contains:');
      buffer.writeln();
      _writeList(buffer, packagesInLayer.map((name) => '`$name`').toList());
    }

    buffer.writeln('## Architecture Layers');
    buffer.writeln();
    for (final layer in sortedLayerNames) {
      final packagesInLayer = (config.layers[layer] ?? []).toList()..sort();
      buffer.writeln('### ${_sentenceCase(layer)}');
      buffer.writeln();
      buffer.writeln('Packages: ${_formatPackages(packagesInLayer)}');
      buffer.writeln();
      buffer.writeln('Responsibilities:');
      buffer.writeln();
      final responsibilities = packagesInLayer
          .map((packageName) => componentsByPackage[packageName])
          .whereType<Component>()
          .map(
            (component) => '${component.name}: ${component.responsibility}',
          )
          .toList()
        ..sort();
      _writeList(buffer, responsibilities);
      buffer.writeln('Public API statistics:');
      buffer.writeln();
      final stats = packagesInLayer.map((packageName) {
        final api = packageApis[packageName];
        final exported = api?.publicSurface.length ?? 0;
        final internal = api?.internalPublicDeclarations.length ?? 0;
        return '`$packageName`: $exported exported symbols, $internal internal public declarations';
      }).toList()
        ..sort();
      _writeList(buffer, stats);
    }

    buffer.writeln('## Component Overview');
    buffer.writeln();
    for (final component in components) {
      buffer.writeln(
        '- ${component.name}: ${component.responsibility}; dependencies: ${_formatPackages(component.dependencies)}; dependents: ${_formatPackages(component.dependents)}',
      );
    }
    buffer.writeln();

    buffer.writeln('## Dependency Flow');
    buffer.writeln();
    final flowStatements = components.map(_dependencyFlowStatement).toList()
      ..sort();
    _writeList(buffer, flowStatements);

    buffer.writeln('## Public API Overview');
    buffer.writeln();
    buffer.writeln('- Total exported symbols: $totalExportedSymbols');
    final exportedByPackage = sortedPackages.map((node) {
      final count = packageApis[node.name]?.publicSurface.length ?? 0;
      return '`${node.name}`: $count';
    }).toList();
    buffer.writeln(
      '- Exported symbols per package: ${exportedByPackage.join(', ')}',
    );
    final largest = packageApis.values.toList()
      ..sort((a, b) {
        final countCompare = b.publicSurface.length.compareTo(
          a.publicSurface.length,
        );
        if (countCompare != 0) return countCompare;
        return a.packageName.compareTo(b.packageName);
      });
    buffer.writeln(
      '- Packages with largest public API: ${largest.take(3).map((api) => '`${api.packageName}` (${api.publicSurface.length})').join(', ')}',
    );
    buffer.writeln();

    buffer.writeln('## Documentation Metadata');
    buffer.writeln();
    buffer.writeln('- Generator: $generatorName');
    buffer.writeln('- Package count: ${sortedPackages.length}');
    buffer.writeln('- Component count: ${components.length}');
    buffer.writeln('- Architecture rule count: ${config.rules.length}');
    if (findings.isNotEmpty) {
      buffer.writeln(
        '- Architecture findings: ${findings.length}; see [remediation guide](${_relativeLink(config.output.narrativeReport, config.output.remediationGuide)}).',
      );
    }
    buffer.writeln();

    return buffer.toString();
  }

  String _generateRisks(
    ArchitectureRiskReport report,
    List<ArchitectureViolation> activeFindings,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Architecture Findings');
    buffer.writeln();
    buffer.writeln(
      'Findings are grouped by severity. Observations are non-failing unless promoted by `risk_rules`.',
    );
    buffer.writeln();

    _writeFindingsSection(
      buffer,
      'Errors',
      activeFindings
          .where((finding) => finding.level == ViolationLevel.error)
          .toList(),
    );
    _writeFindingsSection(
      buffer,
      'Warnings',
      activeFindings
          .where((finding) => finding.level == ViolationLevel.warning)
          .toList(),
    );
    _writeFindingsSection(
      buffer,
      'Observations',
      activeFindings
          .where((finding) => finding.level == ViolationLevel.observation)
          .toList(),
    );

    buffer.writeln('## OK / Healthy Signals');
    buffer.writeln();
    var wroteHealthySignal = false;
    if (activeFindings
        .where((finding) => finding.level == ViolationLevel.error)
        .isEmpty) {
      buffer.writeln('- No validation errors detected.');
      wroteHealthySignal = true;
    }
    if (report.componentsWithUnknownResponsibility.isEmpty) {
      buffer.writeln('- All component responsibilities were classified.');
      wroteHealthySignal = true;
    }
    if (report.packagesWithApiWarnings.isEmpty) {
      buffer.writeln('- No package API warnings detected.');
      wroteHealthySignal = true;
    }
    if (!wroteHealthySignal) {
      buffer.writeln('None detected.');
    }
    buffer.writeln();

    buffer.writeln('## Validation Policy');
    buffer.writeln();
    buffer.writeln(
      'The findings above are documentation-oriented. `validate` reports findings generated by active rules in `arch_doc.yaml` and can promote configured severities to errors.',
    );
    buffer.writeln();
    buffer.writeln('| Policy | Value |');
    buffer.writeln('| --- | --- |');
    buffer.writeln('| `fail_on_risks` | `${config.riskRules.failOnRisks}` |');
    buffer.writeln(
      '| `fail_on_warnings` | `${config.riskRules.failOnWarnings}` |',
    );
    buffer.writeln(
      '| `fail_on_observations` | `${config.riskRules.failOnObservations}` |',
    );
    buffer.writeln();

    return buffer.toString();
  }

  void _writeFindingsSection(
    StringBuffer buffer,
    String title,
    List<ArchitectureViolation> sectionFindings,
  ) {
    buffer.writeln('## $title');
    buffer.writeln();
    final sorted = sectionFindings.toList()..sort(_compareFindings);
    if (sorted.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }

    buffer.writeln('| Severity | Code | Subject | Message | Remediation |');
    buffer.writeln('| --- | --- | --- | --- | --- |');
    final remediationPath = _relativeLink(
      config.output.risksReport,
      config.output.remediationGuide,
    );
    for (final finding in sorted) {
      buffer.writeln(
        '| ${finding.severityLabel} | `${finding.shortCode}` | ${_escapeTableCell(finding.subject)} | ${_escapeTableCell(finding.reason)} | [How to fix]($remediationPath#${finding.remediationAnchor}) |',
      );
    }
    buffer.writeln();
  }

  String _dependencyFlowStatement(Component component) {
    if (component.responsibility == 'Identity abstractions') {
      return 'Authentication abstractions are defined in `${component.packageName}`.';
    }
    if (component.responsibility == 'Windows authentication implementation') {
      return 'Windows-specific authentication functionality is implemented in `${component.packageName}`.';
    }
    if (component.responsibility == 'Linux authentication implementation') {
      return 'Linux-specific authentication functionality is implemented in `${component.packageName}`.';
    }
    if (component.responsibility == 'Shared domain models') {
      return 'Shared domain models are provided by `${component.packageName}`.';
    }
    if (component.responsibility == 'JWT token handling') {
      return 'JWT token handling is provided by `${component.packageName}`.';
    }
    if (component.responsibility == 'Configuration management') {
      return 'Configuration management is provided by `${component.packageName}`.';
    }
    if (component.responsibility == 'gRPC contracts and transport') {
      return 'gRPC contracts and transport are provided by `${component.packageName}`.';
    }
    return '${component.responsibility} is represented by `${component.packageName}`.';
  }

  void _writeList(StringBuffer buffer, List<String> items) {
    if (items.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    for (final item in items) {
      buffer.writeln('- $item');
    }
    buffer.writeln();
  }

  String _formatPackages(List<String> packages) {
    if (packages.isEmpty) return 'None';
    final sorted = packages.toList()..sort();
    return sorted.map((packageName) => '`$packageName`').join(', ');
  }

  String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }

  String _relativeLink(String from, String to) {
    final fromDir = p.posix.dirname(from.replaceAll('\\', '/'));
    final normalizedTo = to.replaceAll('\\', '/');
    final relative = p.posix.relative(normalizedTo, from: fromDir);
    return relative == '.' ? p.posix.basename(normalizedTo) : relative;
  }

  String _escapeTableCell(String value) {
    return value.replaceAll('|', r'\|');
  }
}

int _compareFindings(ArchitectureViolation a, ArchitectureViolation b) {
  final level = _levelRank(a.level).compareTo(_levelRank(b.level));
  if (level != 0) return level;
  final code = a.code.compareTo(b.code);
  if (code != 0) return code;
  final subject = a.subject.compareTo(b.subject);
  if (subject != 0) return subject;
  return a.reason.compareTo(b.reason);
}

int _levelRank(ViolationLevel level) {
  switch (level) {
    case ViolationLevel.error:
      return 0;
    case ViolationLevel.warning:
      return 1;
    case ViolationLevel.observation:
      return 2;
  }
}
