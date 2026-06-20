# Changelog

## 1.0.0

Initial public release of `arch_doc` as a standalone open source project for deterministic architecture documentation and validation in Dart and Flutter workspaces.

### Highlights

- Package-level workspace graph generation with JSON, Mermaid, and PlantUML outputs.
- Architecture layer validation from `arch_doc.yaml`.
- Public API summaries generated from package entrypoints.
- Public surface analysis with export, re-export, `show`, and `hide` support.
- Component discovery with deterministic responsibility heuristics.
- Component markdown plus Mermaid and PlantUML diagram generation.
- Component contract documentation with HLD and LLD views.
- Remediation guide generation for architecture finding codes.
- Architecture narrative and findings reports.
- Deterministic `generate --check` coverage for generated docs and orphan API files.
- Pub.dev-ready package metadata and `arch_doc` command-line executable.

### Known Limitations

- Conditional exports are not supported.
- Fields, method bodies, comments, and docstrings are not analyzed.
- Component responsibilities and architecture narratives are heuristic and do not use LLMs or external APIs.
- Pub.dev publishing requires owner credentials and manual confirmation.
