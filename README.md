# arch_doc

`arch_doc` generates deterministic architecture documentation and validation reports for Dart and Flutter workspaces. It scans local packages, builds dependency graphs, documents public APIs, discovers components and contracts, and checks package-layer rules from a simple YAML configuration.

The project is designed for teams that want architecture documentation to stay close to the code and remain verifiable in CI.

## Why Use It

- Generate repeatable Markdown architecture docs without external services.
- Visualize package and component dependencies with Mermaid and PlantUML sources.
- Detect missing or unused local dependencies from actual Dart imports.
- Document package public APIs from `lib\<package>.dart` entrypoints.
- Track architecture findings with stable codes and remediation guidance.
- Keep architecture rules reviewable in `arch_doc.yaml`.

## Supported Projects

Supported:

- Dart package workspaces
- Flutter package workspaces
- Multi-package repositories
- Single-package Dart or Flutter libraries
- Projects that expose public APIs through `lib\<package>.dart`

Partially supported:

- Custom package layouts
- Packages without a public entrypoint
- Workspaces with local `path` dependencies outside the analyzed root

Not currently supported:

- Conditional export analysis
- Git dependency scanning
- Method-body analysis
- LLM-generated documentation

## Quick Start For Windows

From this repository:

```powershell
Set-Location arch_doc
dart pub get
dart run bin\arch_doc.dart --root example generate
dart run bin\arch_doc.dart --root example validate
```

The generated example documentation is written to:

```text
arch_doc\example\doc\arch_doc
```

To use `arch_doc` in another workspace, add an `arch_doc.yaml` file to that workspace and run:

```powershell
Set-Location C:\path\to\your_workspace
dart run arch_doc\bin\arch_doc.dart generate
dart run arch_doc\bin\arch_doc.dart validate
```

## CLI Usage

```powershell
dart run bin\arch_doc.dart --root C:\path\to\workspace generate
dart run bin\arch_doc.dart --root C:\path\to\workspace generate --check
dart run bin\arch_doc.dart --root C:\path\to\workspace generate --dependency-source used
dart run bin\arch_doc.dart --root C:\path\to\workspace validate
dart run bin\arch_doc.dart --root C:\path\to\workspace --config C:\path\to\arch_doc.yaml validate
```

Options:

| Option | Applies to | Description |
| --- | --- | --- |
| `--root <path>` | all commands | Workspace root to analyze. Defaults to the current directory. |
| `--config <path>` | all commands | Explicit path to `arch_doc.yaml`. |
| `--check` | `generate` | Fails when generated files are out of date. |
| `--dependency-source <declared|used>` | `generate` | Chooses whether diagrams use `pubspec.yaml` dependencies or actual Dart imports. |

## Configuration Overview

`arch_doc` looks for configuration in this order:

1. The path passed with `--config`.
2. `arch_doc.yaml` in the workspace root.
3. `tools\arch_doc\config\arch_doc.yaml` for legacy embedded checkouts.

A minimal configuration:

```yaml
output:
  root: doc/arch_doc

layers:
  core:
    packages:
      - sample_core
  contracts:
    packages:
      - sample_contracts
  applications:
    packages:
      - sample_app

rules:
  - name: core_must_not_depend_on_applications
    from_layer: core
    forbidden_layers:
      - applications

excluded_packages:
  - arch_doc
```

See `config\arch_doc.yaml` for a reusable template and `example\arch_doc.yaml` for a working sample.

## Generated Artifacts

By default, generated files are written under `doc\arch_doc` in the analyzed workspace.

| Path | Description |
| --- | --- |
| `README.md` | Architecture overview and reading path. |
| `data\workspace_graph.json` | Machine-readable package graph. |
| `diagrams\packages.mmd` | Mermaid package dependency diagram. |
| `diagrams\packages.puml` | PlantUML package dependency diagram. |
| `reports\components.md` | Component catalog. |
| `reports\narrative.md` | Deterministic architecture narrative. |
| `reports\risks.md` | Architecture findings report. |
| `remediation.md` | Finding-code remediation guide. |
| `contracts.md` | Component contract catalog. |
| `components\*.md` | Per-component contract documentation. |
| `api\*.md` | Per-package public API summaries. |

## Validation And Finding Codes

`validate` exits with code `1` only when errors are present. Warnings and observations are reported without failing unless promoted by `risk_rules`.

Current finding groups include:

- `ARCH*`: layer and dependency-rule findings.
- `API*`: public entrypoint, export, and public-surface findings.
- `COMP*`: component discovery and responsibility findings.
- `CONTRACT*`: component contract findings.

Generated reports link findings to `remediation.md`.

## Example Project

The `example` directory contains a small neutral workspace:

```text
example\packages\sample_core
example\packages\sample_contracts
example\packages\sample_app
example\arch_doc.yaml
```

Run it with:

```powershell
Set-Location arch_doc
dart run bin\arch_doc.dart --root example generate
dart run bin\arch_doc.dart --root example generate --check
dart run bin\arch_doc.dart --root example validate
```

## Contributing

Contributions are welcome. Good starting points include documentation improvements, example scenarios, diagnostics, finding-code explanations, and CI integration.

Read:

- `CONTRIBUTING.md`
- `docs\development.md`
- `docs\roadmap.md`

## Roadmap

The project roadmap is maintained in `docs\roadmap.md`. It includes dependency graph visualization, Mermaid export improvements, CI integration, a GitHub Action, improved Flutter support, advanced architecture rules, and monorepo improvements.

## License

MIT. See `LICENSE`.
