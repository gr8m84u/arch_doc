import 'package:test/test.dart';
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('MarkdownGenerator', () {
    test('generates deterministic markdown (snapshot test)', () {
      final nodes = [
        PackageNode(
          name: 'pkg_a',
          path: 'packages/pkg_a',
          description: 'Desc A',
          declaredDependencies: [],
          usedDependencies: [],
        ),
        PackageNode(
          name: 'pkg_b',
          path: 'packages/pkg_b',
          description: 'Desc B',
          declaredDependencies: ['pkg_a'],
          usedDependencies: ['pkg_a'],
        ),
      ];
      final config = ArchConfig(
        layers: {
          'impl': ['pkg_b'],
          'core': ['pkg_a'],
        },
        rules: [
          ArchRule(
            name: 'core_rule',
            fromLayer: 'core',
            forbiddenLayers: ['impl'],
          ),
        ],
      );

      final generator = MarkdownGenerator(
        nodes: nodes,
        config: config,
        packageApis: {
          'pkg_a': PackageApi(
            packageName: 'pkg_a',
            description: 'Desc A',
            publicSurface: [
              ApiDeclaration(
                name: 'A',
                kind: ApiDeclarationKind.classDeclaration,
                libraryPath: 'pkg_a.dart',
              ),
            ],
            internalPublicDeclarations: [],
          ),
          'pkg_b': PackageApi(
            packageName: 'pkg_b',
            description: 'Desc B',
            publicSurface: [],
            internalPublicDeclarations: [
              ApiDeclaration(
                name: 'InternalB',
                kind: ApiDeclarationKind.classDeclaration,
                libraryPath: 'src/internal.dart',
              ),
            ],
            warnings: ['Missing public entrypoint `lib/pkg_b.dart`.'],
          ),
        },
        narrativeHealth: NarrativeHealth(
          riskCount: 1,
          observationCount: 2,
          warningCount: 3,
        ),
      );
      final markdown = generator.generate();

      final expected = '''
<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->
# Architecture Overview

## Architecture status

Architecture status: OK

See [remediation.md](./remediation.md) for the severity model and remediation guidance.

## Recommended reading path

1. Package overview
2. Component catalog
3. Component docs for contracts and implementations
4. Architecture findings
5. Remediation guide

In SDK/library workspaces, observations about missing dependents or missing dependencies are often expected and do not indicate a failure.

## Package layers

### Layer: impl

| Package | Description | Public API |
| --- | --- | --- |
| `pkg_b` | Desc B | [View API](./api/pkg_b.md) |

### Layer: core

| Package | Description | Public API |
| --- | --- | --- |
| `pkg_a` | Desc A | [View API](./api/pkg_a.md) |

## Dependency health

### Declared but unused dependencies
None

### Used but not declared dependencies
None

### Packages with no local dependencies
- `pkg_a`

### Packages not assigned to any architecture layer
None

## Public API health

| Package | Exported symbols | Internal public declarations | API warnings |
| --- | ---: | ---: | --- |
| `pkg_a` | 1 | 0 | None |
| `pkg_b` | 0 | 1 | Missing public entrypoint `lib/pkg_b.dart`. |

## Architecture Components

- [components.md](./reports/components.md): Discovered architecture components and responsibilities.
- [components.mmd](./diagrams/components.mmd): Mermaid component dependency diagram.
- [components.puml](./diagrams/components.puml): PlantUML component dependency diagram.

## Component Contracts

Per-component contract documentation contains separate HLD and LLD views. HLD diagrams show package-level relationships; LLD diagrams show interfaces, implementation classes, and direct request/response models.

- [contracts.md](./contracts.md): Global contract catalog.
- [contracts.mmd](./contracts.mmd): Mermaid global contract diagram.
- [contracts.puml](./contracts.puml): PlantUML global contract diagram.
- [components/](./components/): Per-component contract documentation with Mermaid and PlantUML HLD/LLD diagrams.

No contract data available.

## Architecture Narratives

- [narrative.md](./reports/narrative.md): Generated architecture narrative.
- [risks.md](./reports/risks.md): Architecture Findings report.
- [remediation.md](./remediation.md): Finding codes and remediation guide.

## Narrative health

| Risks | Observations | Warnings |
| ---: | ---: | ---: |
| 1 | 2 | 3 |

## Architecture Rules v2

Severity model:

- `error`: fails `validate` with exit code 1.
- `warning`: reported by `validate`, but does not fail by default.
- `observation`: neutral architecture fact reported by `validate`, but does not fail by default.

### API rules

| Rule | Value |
| --- | --- |
| `require_public_entrypoint` | `true` |
| `forbid_exports_from_src` | `false` |
| `warn_internal_public_declarations` | `true` |
| `max_exported_symbols_per_package` | `null` |

### Component rules

| Rule | Value |
| --- | --- |
| `require_known_responsibility` | `true` |
| `warn_without_public_api` | `true` |
| `warn_without_dependents` | `true` |
| `warn_without_dependencies` | `true` |

### Risk policy

| Rule | Value |
| --- | --- |
| `fail_on_risks` | `false` |
| `fail_on_warnings` | `false` |
| `fail_on_observations` | `false` |

## Architecture Evolution

- **M1 Package-level architecture docs**: workspace graph, package layers, and dependency rules.
- **M2 Public API summary**: per-package public declaration summaries.
- **M3 Public Surface Analysis**: exported API detection from package entrypoints.
- **M4 Component Discovery**: component responsibilities and component dependency diagram.
- **M5 Architecture Narratives**: generated architecture narrative and risks/observations.
- **M6 Architecture Rules v2**: API, component, and risk-policy validation.

## Package dependency diagram

See [packages.mmd](./diagrams/packages.mmd) for the full diagram.

## Architecture rules

- **core_rule**: Layer `core` cannot depend on:
  - `impl`

## Validation status

This document is automatically generated. To ensure the workspace adheres to these rules, run:

```powershell
dart run arch_doc validate
```

## Generated Artifacts

- Local package count: 2
- External package count: 0

- [workspace_graph.json](./data/workspace_graph.json): Machine-readable dependency graph.
- [packages.mmd](./diagrams/packages.mmd): Mermaid.js package dependency diagram source.
- [packages.puml](./diagrams/packages.puml): PlantUML package dependency diagram source.
- [components.md](./reports/components.md): Discovered architecture components and responsibilities.
- [components.mmd](./diagrams/components.mmd): Mermaid component dependency diagram source.
- [components.puml](./diagrams/components.puml): PlantUML component dependency diagram source.
- [narrative.md](./reports/narrative.md): Generated architecture narrative.
- [risks.md](./reports/risks.md): Architecture Findings report.
- [remediation.md](./remediation.md): Remediation guide for finding codes.
- [contracts.md](./contracts.md): Component contract documentation.
- [contracts.mmd](./contracts.mmd): Mermaid component contract diagram source.
- [contracts.puml](./contracts.puml): PlantUML component contract diagram source.
- [api/](./api/): Per-package public API summaries.
''';

      expect(markdown.trim(), expected.trim());
    });

    test('renders architecture status counts for findings', () {
      final markdown = MarkdownGenerator(
        nodes: const [],
        config: ArchConfig(layers: const {}, rules: const []),
        findings: [
          ArchitectureViolation(
            ruleName: 'warn_internal_public_declarations',
            packageName: 'pkg',
            dependencyName: 'N/A',
            reason: 'has 1 internal public declarations.',
            level: ViolationLevel.warning,
            category: 'api',
            subject: 'pkg',
          ),
          ArchitectureViolation(
            ruleName: 'warn_without_dependents',
            packageName: 'pkg',
            dependencyName: 'N/A',
            reason: 'has no dependents detected in workspace.',
            level: ViolationLevel.observation,
            category: 'component',
            subject: 'Pkg Component',
          ),
        ],
      ).generate();

      expect(markdown, contains('| Errors | 0 |'));
      expect(markdown, contains('| Warnings | 1 |'));
      expect(markdown, contains('| Observations | 1 |'));
      expect(markdown, isNot(contains('Architecture status: OK')));
    });

    test('renders recommended reading path and SDK/library observation note',
        () {
      final markdown = MarkdownGenerator(
        nodes: const [],
        config: ArchConfig(layers: const {}, rules: const []),
      ).generate();

      expect(markdown, contains('## Recommended reading path'));
      expect(markdown, contains('1. Package overview'));
      expect(
        markdown,
        contains(
          'In SDK/library workspaces, observations about missing dependents or missing dependencies are often expected and do not indicate a failure.',
        ),
      );
    });

    test('embeds package diagram when inline_mermaid is enabled and small', () {
      final config = ArchConfig(
        layers: const {},
        rules: const [],
        diagramEmbedding: DiagramEmbeddingConfig(mode: 'inline_mermaid'),
      );
      final markdown = MarkdownGenerator(
        nodes: const [],
        config: config,
        packageDiagramMermaid: 'graph TD\n  A --> B',
      ).generate();

      expect(markdown, contains('## Package dependency diagram'));
      expect(markdown, contains('```mermaid'));
      expect(markdown, contains('graph TD\n  A --> B'));
    });

    test('shows link instead of embedding when diagram is too large', () {
      final config = ArchConfig(
        layers: const {},
        rules: const [],
        diagramEmbedding: DiagramEmbeddingConfig(mode: 'inline_mermaid'),
      );
      final largeDiagram = 'graph TD\n' + ('  A --> B\n' * 500);
      final markdown = MarkdownGenerator(
        nodes: const [],
        config: config,
        packageDiagramMermaid: largeDiagram,
      ).generate();

      expect(markdown, contains('## Package dependency diagram'));
      expect(markdown, isNot(contains('```mermaid')));
      expect(markdown, contains('too large to embed'));
      expect(markdown, contains('[packages.mmd](./diagrams/packages.mmd)'));
    });

    test('shows only link when inline_mermaid is disabled', () {
      final config = ArchConfig(
        layers: const {},
        rules: const [],
        diagramEmbedding: DiagramEmbeddingConfig(mode: 'link_only'),
      );
      final markdown = MarkdownGenerator(
        nodes: const [],
        config: config,
        packageDiagramMermaid: 'graph TD\n  A --> B',
      ).generate();

      expect(markdown, contains('## Package dependency diagram'));
      expect(markdown, isNot(contains('```mermaid')));
      expect(markdown, contains('See [packages.mmd](./diagrams/packages.mmd)'));
    });
  });
}
