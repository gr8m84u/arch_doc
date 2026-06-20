import '../component/component_discovery.dart';
import '../component/component_models.dart';
import '../config/arch_config.dart';
import '../model/api_models.dart';
import 'architecture_violation.dart';

class RulesV2Validator {
  final ArchConfig config;
  final Map<String, PackageApi> packageApis;
  final ComponentGraph componentGraph;

  RulesV2Validator({
    required this.config,
    required this.packageApis,
    required this.componentGraph,
  });

  List<ArchitectureViolation> validate() {
    final findings = <ArchitectureViolation>[
      ..._validateApiRules(),
      ..._validateComponentRules(),
    ];
    return _applyRiskPolicy(findings)..sort(compareFindings);
  }

  List<ArchitectureViolation> _validateApiRules() {
    final findings = <ArchitectureViolation>[];
    final apis = packageApis.values.toList()
      ..sort((a, b) => a.packageName.compareTo(b.packageName));

    for (final api in apis) {
      final missingEntrypointWarning =
          'Missing public entrypoint `lib/${api.packageName}.dart`.';

      if (config.apiRules.requirePublicEntrypoint &&
          api.warnings.contains(missingEntrypointWarning)) {
        findings.add(
          _finding(
            category: 'api',
            subject: api.packageName,
            ruleName: 'require_public_entrypoint',
            reason:
                'is missing public entrypoint `lib/${api.packageName}.dart`.',
            level: ViolationLevel.error,
            isRisk: true,
          ),
        );
      }

      for (final warning in api.warnings.where(
        (w) => w != missingEntrypointWarning,
      )) {
        findings.add(
          _finding(
            category: 'api',
            subject: api.packageName,
            ruleName: 'api_warning',
            reason: warning,
            level: ViolationLevel.warning,
            isRisk: true,
          ),
        );
      }

      if (config.apiRules.forbidExportsFromSrc) {
        final srcExports = api.publicSurface
            .where(
              (declaration) => declaration.libraryPath.startsWith('src/'),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final declaration in srcExports) {
          findings.add(
            _finding(
              category: 'api',
              subject: api.packageName,
              ruleName: 'forbid_exports_from_src',
              reason:
                  'exports `${declaration.name}` from `lib/${declaration.libraryPath}`.',
              level: ViolationLevel.error,
              isRisk: true,
            ),
          );
        }
      }

      if (config.apiRules.warnInternalPublicDeclarations &&
          api.internalPublicDeclarations.isNotEmpty) {
        findings.add(
          _finding(
            category: 'api',
            subject: api.packageName,
            ruleName: 'warn_internal_public_declarations',
            reason:
                'has ${api.internalPublicDeclarations.length} internal public declarations.',
            level: ViolationLevel.warning,
          ),
        );
      }

      final maxExported = config.apiRules.maxExportedSymbolsPerPackage;
      if (maxExported != null && api.publicSurface.length > maxExported) {
        findings.add(
          _finding(
            category: 'api',
            subject: api.packageName,
            ruleName: 'max_exported_symbols_per_package',
            reason:
                'exports ${api.publicSurface.length} symbols, exceeding configured limit $maxExported.',
            level: ViolationLevel.warning,
            isRisk: true,
          ),
        );
      }
    }

    return findings;
  }

  List<ArchitectureViolation> _validateComponentRules() {
    final findings = <ArchitectureViolation>[];
    final components = componentGraph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final component in components) {
      if (config.componentRules.requireKnownResponsibility &&
          component.responsibility ==
              ResponsibilityExtractor.unknownResponsibility) {
        findings.add(
          _finding(
            category: 'component',
            subject: component.name,
            packageName: component.packageName,
            ruleName: 'require_known_responsibility',
            reason: 'has unknown responsibility.',
            level: ViolationLevel.warning,
            isRisk: true,
          ),
        );
      }

      if (config.componentRules.warnWithoutPublicApi &&
          component.exportedSymbolCount == 0) {
        findings.add(
          _finding(
            category: 'component',
            subject: component.name,
            packageName: component.packageName,
            ruleName: 'warn_without_public_api',
            reason: 'has no public API.',
            level: ViolationLevel.warning,
            isRisk: true,
          ),
        );
      }

      if (config.componentRules.warnWithoutDependents &&
          component.dependents.isEmpty) {
        findings.add(
          _finding(
            category: 'component',
            subject: component.name,
            packageName: component.packageName,
            ruleName: 'warn_without_dependents',
            reason: 'has no dependents detected in workspace.',
            level: ViolationLevel.observation,
          ),
        );
      }

      if (config.componentRules.warnWithoutDependencies &&
          component.dependencies.isEmpty) {
        findings.add(
          _finding(
            category: 'component',
            subject: component.name,
            packageName: component.packageName,
            ruleName: 'warn_without_dependencies',
            reason: 'has no dependencies detected.',
            level: ViolationLevel.observation,
          ),
        );
      }
    }

    return findings;
  }

  List<ArchitectureViolation> _applyRiskPolicy(
    List<ArchitectureViolation> findings,
  ) {
    return findings.map((finding) {
      if (config.riskRules.failOnWarnings &&
          finding.level == ViolationLevel.warning) {
        return finding.copyWith(level: ViolationLevel.error);
      }
      if (config.riskRules.failOnObservations &&
          finding.level == ViolationLevel.observation) {
        return finding.copyWith(level: ViolationLevel.error);
      }
      if (config.riskRules.failOnRisks && finding.isRisk) {
        return finding.copyWith(level: ViolationLevel.error);
      }
      return finding;
    }).toList();
  }

  ArchitectureViolation _finding({
    required String category,
    required String subject,
    required String ruleName,
    required String reason,
    required ViolationLevel level,
    String? packageName,
    bool isRisk = false,
  }) {
    return ArchitectureViolation(
      ruleName: ruleName,
      packageName: packageName ?? subject,
      dependencyName: 'N/A',
      reason: reason,
      level: level,
      category: category,
      subject: subject,
      isRisk: isRisk,
    );
  }
}

int compareFindings(ArchitectureViolation a, ArchitectureViolation b) {
  final severityCompare = _severityRank(
    a.level,
  ).compareTo(_severityRank(b.level));
  if (severityCompare != 0) return severityCompare;
  final codeCompare = a.code.compareTo(b.code);
  if (codeCompare != 0) return codeCompare;
  final categoryCompare = a.category.compareTo(b.category);
  if (categoryCompare != 0) return categoryCompare;
  final subjectCompare = a.subject.compareTo(b.subject);
  if (subjectCompare != 0) return subjectCompare;
  return a.reason.compareTo(b.reason);
}

int _severityRank(ViolationLevel level) {
  switch (level) {
    case ViolationLevel.error:
      return 0;
    case ViolationLevel.warning:
      return 1;
    case ViolationLevel.observation:
      return 2;
  }
}
