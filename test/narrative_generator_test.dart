import 'package:test/test.dart';
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('ArchitectureNarrativeGenerator', () {
    test('generates deterministic architecture narrative', () {
      final narrative = buildNarrativeFixture();

      expect(
        narrative.narrativeMarkdown.trim(),
        '''
<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->
# Architecture Narrative

## System Overview

The workspace contains 2 packages organized into 2 architecture layers.

Core layer contains:

- `pkg_core`

Impl layer contains:

- `pkg_impl`

## Architecture Layers

### Core

Packages: `pkg_core`

Responsibilities:

- Core Component: Shared domain models

Public API statistics:

- `pkg_core`: 2 exported symbols, 1 internal public declarations

### Impl

Packages: `pkg_impl`

Responsibilities:

- Impl Component: Unknown responsibility

Public API statistics:

- `pkg_impl`: 0 exported symbols, 0 internal public declarations

## Component Overview

- Core Component: Shared domain models; dependencies: None; dependents: `pkg_impl`
- Impl Component: Unknown responsibility; dependencies: `pkg_core`; dependents: None

## Dependency Flow

- Shared domain models are provided by `pkg_core`.
- Unknown responsibility is represented by `pkg_impl`.

## Public API Overview

- Total exported symbols: 2
- Exported symbols per package: `pkg_core`: 2, `pkg_impl`: 0
- Packages with largest public API: `pkg_core` (2), `pkg_impl` (0)

## Documentation Metadata

- Generator: arch_doc narrative v1
- Package count: 2
- Component count: 2
- Architecture rule count: 1
- Architecture findings: 6; see [remediation guide](../remediation.md).
'''
            .trim(),
      );
      expect(narrative.health.riskCount, 1);
      expect(narrative.health.observationCount, 2);
      expect(narrative.health.warningCount, 3);
    });
  });
}

ArchitectureNarrative buildNarrativeFixture() {
  return ArchitectureNarrativeGenerator(
    packages: [
      _node('pkg_core'),
      _node('pkg_impl', usedDependencies: ['pkg_core']),
    ],
    componentGraph: ComponentGraph(
      components: [
        Component(
          name: 'Core Component',
          packageName: 'pkg_core',
          responsibility: 'Shared domain models',
          dependencies: [],
          dependents: ['pkg_impl'],
          exportedSymbolCount: 2,
          keyExportedSymbols: [_declaration('CoreA'), _declaration('CoreB')],
        ),
        Component(
          name: 'Impl Component',
          packageName: 'pkg_impl',
          responsibility: ResponsibilityExtractor.unknownResponsibility,
          dependencies: ['pkg_core'],
          dependents: [],
          exportedSymbolCount: 0,
          keyExportedSymbols: [],
        ),
      ],
    ),
    config: ArchConfig(
      layers: {
        'core': ['pkg_core'],
        'impl': ['pkg_impl'],
      },
      rules: [
        ArchRule(
          name: 'core_rule',
          fromLayer: 'core',
          forbiddenLayers: ['impl'],
        ),
      ],
    ),
    packageApis: {
      'pkg_core': PackageApi(
        packageName: 'pkg_core',
        description: '',
        publicSurface: [_declaration('CoreA'), _declaration('CoreB')],
        internalPublicDeclarations: [_declaration('InternalCore')],
      ),
      'pkg_impl': PackageApi(
        packageName: 'pkg_impl',
        description: '',
        publicSurface: [],
        internalPublicDeclarations: [],
        warnings: ['Missing public entrypoint `lib/pkg_impl.dart`.'],
      ),
    },
    findings: [
      ArchitectureViolation(
        ruleName: 'require_public_entrypoint',
        packageName: 'pkg_impl',
        dependencyName: 'N/A',
        reason: 'is missing public entrypoint `lib/pkg_impl.dart`.',
        level: ViolationLevel.error,
        category: 'api',
        subject: 'pkg_impl',
        isRisk: true,
      ),
      ArchitectureViolation(
        ruleName: 'warn_internal_public_declarations',
        packageName: 'pkg_core',
        dependencyName: 'N/A',
        reason: 'has 1 internal public declarations.',
        level: ViolationLevel.warning,
        category: 'api',
        subject: 'pkg_core',
      ),
      ArchitectureViolation(
        ruleName: 'require_known_responsibility',
        packageName: 'pkg_impl',
        dependencyName: 'N/A',
        reason: 'has unknown responsibility.',
        level: ViolationLevel.warning,
        category: 'component',
        subject: 'Impl Component',
        isRisk: true,
      ),
      ArchitectureViolation(
        ruleName: 'warn_without_public_api',
        packageName: 'pkg_impl',
        dependencyName: 'N/A',
        reason: 'has no public API.',
        level: ViolationLevel.warning,
        category: 'component',
        subject: 'Impl Component',
        isRisk: true,
      ),
      ArchitectureViolation(
        ruleName: 'warn_without_dependencies',
        packageName: 'pkg_core',
        dependencyName: 'N/A',
        reason: 'has no dependencies.',
        level: ViolationLevel.observation,
        category: 'component',
        subject: 'Core Component',
      ),
      ArchitectureViolation(
        ruleName: 'warn_without_dependents',
        packageName: 'pkg_impl',
        dependencyName: 'N/A',
        reason: 'has no dependents.',
        level: ViolationLevel.observation,
        category: 'component',
        subject: 'Impl Component',
      ),
    ],
  ).generate();
}

PackageNode _node(String name, {List<String> usedDependencies = const []}) {
  return PackageNode(
    name: name,
    path: 'packages/$name',
    description: '',
    declaredDependencies: [],
    usedDependencies: usedDependencies,
  );
}

ApiDeclaration _declaration(String name) {
  return ApiDeclaration(
    name: name,
    kind: ApiDeclarationKind.classDeclaration,
    libraryPath: 'src/$name.dart',
  );
}
