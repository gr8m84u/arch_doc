import '../config/arch_config.dart';
import '../workspace/workspace_graph.dart';
import 'architecture_violation.dart';

class ArchValidator {
  final ArchConfig config;
  final List<PackageNode> nodes;
  final DependencySource dependencySource;

  ArchValidator({
    required this.config,
    required this.nodes,
    this.dependencySource = DependencySource.used,
  });

  List<ArchitectureViolation> validate() {
    final violations = <ArchitectureViolation>[];
    final packageToLayer = <String, String>{};
    final knownPackageNames = nodes.map((n) => n.name).toSet();

    // Map packages to layers
    config.layers.forEach((layerName, packages) {
      for (final pkg in packages) {
        packageToLayer[pkg] = layerName;
      }
    });

    // Check for non-existent packages in config
    for (final pkg in packageToLayer.keys) {
      if (!knownPackageNames.contains(pkg) &&
          !config.excludedPackages.contains(pkg)) {
        violations.add(
          ArchitectureViolation(
            ruleName: 'config_error',
            packageName: pkg,
            dependencyName: 'N/A',
            reason:
                'Package "$pkg" defined in configuration but not found in workspace.',
          ),
        );
      }
    }

    // Check each package in workspace
    for (final node in nodes) {
      if (config.excludedPackages.contains(node.name)) continue;

      final layer = packageToLayer[node.name];
      if (layer == null) {
        violations.add(
          ArchitectureViolation(
            ruleName: 'unassigned_package',
            packageName: node.name,
            dependencyName: 'N/A',
            reason:
                'Package "${node.name}" is not assigned to any layer in arch_doc.yaml.',
            level: ViolationLevel.warning,
          ),
        );
        continue;
      }

      // Find rules for this layer
      final layerRules =
          config.rules.where((r) => r.fromLayer == layer).toList();

      final deps = dependencySource == DependencySource.declared
          ? node.declaredDependencies
          : node.usedDependencies;

      for (final depName in deps) {
        if (config.excludedPackages.contains(depName)) continue;

        final depLayer = packageToLayer[depName];
        if (depLayer == null) continue;

        for (final rule in layerRules) {
          if (rule.forbiddenLayers.contains(depLayer)) {
            violations.add(
              ArchitectureViolation(
                ruleName: rule.name,
                packageName: node.name,
                dependencyName: depName,
                reason:
                    'layer "$layer" cannot depend on "$depLayer" (source: $dependencySource)',
              ),
            );
          }
        }
      }
    }

    violations.sort((a, b) {
      final levelComp = _levelRank(a.level).compareTo(_levelRank(b.level));
      if (levelComp != 0) return levelComp;
      final pkgComp = a.packageName.compareTo(b.packageName);
      if (pkgComp != 0) return pkgComp;
      final ruleComp = a.ruleName.compareTo(b.ruleName);
      if (ruleComp != 0) return ruleComp;
      return a.dependencyName.compareTo(b.dependencyName);
    });

    return violations;
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
}
