# Contributing

Thanks for helping improve `arch_doc`. The project is intentionally small, deterministic, and friendly to documentation-first contributions.

## Windows Setup

```powershell
Set-Location arch_doc
dart pub get
dart test
dart analyze
```

## Development Workflow

1. Keep changes focused and easy to review.
2. Add or update tests for behavior changes.
3. Update README or docs when user-facing behavior changes.
4. Run formatting before opening a pull request:

```powershell
dart format .
```

5. Run verification:

```powershell
dart test
dart analyze
dart run bin\arch_doc.dart --root example generate --check
dart run bin\arch_doc.dart --root example validate
```

## Adding Finding Codes

When adding a finding code:

- Define the code and remediation text in the validation layer.
- Add tests for severity, message, and remediation link.
- Update documentation when the finding affects users.
- Keep messages deterministic and actionable.

## Documentation Changes

Documentation should be English-first and use Windows or PowerShell examples. Avoid private project names, organization-specific context, and platform assumptions that are not required by the tool.
