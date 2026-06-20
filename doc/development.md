# Development Guide

`arch_doc` is organized as a deterministic analysis and generation pipeline.

## Main Subsystems

- Workspace discovery finds Dart and Flutter packages under the selected root and can optionally include external filesystem `path` packages.
- Import analysis scans Dart files in `lib` and compares actual imports with declared `pubspec.yaml` dependencies.
- API analysis starts from `lib\<package>.dart`, follows exports, and separates exported API from internal public declarations.
- Component discovery creates architecture components from packages, dependencies, public API, and deterministic naming heuristics.
- Contract analysis detects interfaces, abstract classes, service-style classes, implementations, and request or response model references.
- Markdown generation writes architecture overviews, component catalogs, API summaries, findings, remediation guides, and diagram sources.
- Validation applies layer rules, API rules, component rules, contract findings, and risk-policy promotion.

## Local Verification

```powershell
Set-Location arch_doc
dart pub get
dart test
dart analyze
```

## Design Principles

- Deterministic output is more important than clever prose.
- Diagnostics should be stable enough for CI and documentation review.
- Generated files should be useful in plain Markdown viewers.
- The tool should remain local-first and avoid external services.
