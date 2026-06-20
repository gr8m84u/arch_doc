import 'finding_definition.dart';

class RemediationGuideGenerator {
  String generate() {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Remediation Guide');
    buffer.writeln();
    buffer.writeln('## Severity Model');
    buffer.writeln();
    buffer.writeln('- OK: informational status, no action required.');
    buffer.writeln('- Observation: neutral signal, review if unexpected.');
    buffer.writeln('- Warning: likely architecture smell, review and decide.');
    buffer.writeln('- Error: must be fixed or explicitly reconfigured.');
    buffer.writeln();
    buffer.writeln('## Finding Codes');
    buffer.writeln();

    final definitions = FindingRegistry.all.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    for (final definition in definitions) {
      buffer.writeln('### ${definition.shortCode} ${definition.title}');
      buffer.writeln();
      buffer.writeln('Severity: ${_severityLabel(definition.severity)}');
      buffer.writeln();
      buffer.writeln('Meaning:');
      buffer.writeln(definition.description);
      buffer.writeln();
      buffer.writeln('Why it matters:');
      buffer.writeln(_whyItMatters(definition));
      buffer.writeln();
      buffer.writeln('How to fix:');
      _writeRemediation(buffer, definition.remediation);
      buffer.writeln();
      buffer.writeln('Configuration:');
      buffer.writeln('`${definition.configuration}`');
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _severityLabel(FindingSeverity severity) {
    switch (severity) {
      case FindingSeverity.ok:
        return 'OK';
      case FindingSeverity.observation:
        return 'Observation';
      case FindingSeverity.warning:
        return 'Warning';
      case FindingSeverity.error:
        return 'Error';
    }
  }

  String _whyItMatters(FindingDefinition definition) {
    switch (definition.code) {
      case 'API001_MISSING_PUBLIC_ENTRYPOINT':
        return 'Public surface analysis cannot reliably determine the exported API.';
      case 'ARCH002_DUPLICATE_PACKAGE_NAME':
        return 'Generated reports and validators index packages by package name.';
      case 'DISC001_EXTERNAL_PATH_NOT_FOUND':
        return 'Architecture reports may miss packages that are referenced outside the command root.';
      default:
        return 'It affects how clearly the generated architecture reports describe ownership, dependencies, and public API boundaries.';
    }
  }

  void _writeRemediation(StringBuffer buffer, String remediation) {
    final parts = remediation.split(', ');
    if (parts.length < 2) {
      buffer.writeln('1. $remediation');
      return;
    }
    for (var i = 0; i < parts.length; i++) {
      final text = i == parts.length - 1 ? parts[i] : '${parts[i]},';
      buffer.writeln('${i + 1}. $text');
    }
  }
}
