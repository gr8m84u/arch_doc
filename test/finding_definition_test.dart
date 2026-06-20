import 'package:arch_doc/arch_doc.dart';
import 'package:test/test.dart';

void main() {
  group('FindingRegistry', () {
    test('maps stable finding codes and anchors', () {
      final definition = FindingRegistry.forRule('require_public_entrypoint');

      expect(definition.code, 'API001_MISSING_PUBLIC_ENTRYPOINT');
      expect(definition.shortCode, 'API001');
      expect(definition.severity, FindingSeverity.error);
      expect(definition.docsAnchor, 'api001-missing-public-entrypoint');
    });

    test('falls back architecture rules to ARCH001', () {
      final definition = FindingRegistry.forRule('custom_layer_rule');

      expect(definition.code, 'ARCH001_PACKAGE_LAYER_VIOLATION');
    });

    test('maps contract finding codes', () {
      expect(
        FindingRegistry.forRule('contract_unknown_protocol').code,
        'CONTRACT001_UNKNOWN_PROTOCOL',
      );
      expect(
        FindingRegistry.forRule('contract_consumer_unknown').code,
        'CONTRACT002_CONSUMER_UNKNOWN',
      );
      expect(
        FindingRegistry.forRule(
          'contract_implementation_without_exported_interface',
        ).code,
        'CONTRACT005_IMPLEMENTATION_WITHOUT_EXPORTED_INTERFACE',
      );
    });
  });

  group('RemediationGuideGenerator', () {
    test('generates deterministic remediation guide anchors', () {
      final markdown = RemediationGuideGenerator().generate();

      expect(markdown, contains('# Remediation Guide'));
      expect(markdown, contains('## Severity Model'));
      expect(markdown, contains('### API001 Missing public entrypoint'));
      expect(markdown, contains('`api_rules.require_public_entrypoint`'));
      expect(markdown, contains('### API003 Internal public declarations'));
      expect(markdown, contains('### CONTRACT001 Unknown contract protocol'));
      expect(markdown, isNot(contains('### API003 Missing public entrypoint')));
    });
  });

  group('ArchitectureViolation', () {
    test('renders code and remediation path for CLI output', () {
      final finding = ArchitectureViolation(
        ruleName: 'warn_internal_public_declarations',
        packageName: 'pkg',
        dependencyName: 'N/A',
        reason: 'has 1 internal public declarations.',
        level: ViolationLevel.warning,
        category: 'api',
        subject: 'pkg',
      );

      expect(
        finding.reportLine,
        '[API003] [api] pkg has 1 internal public declarations.',
      );
      expect(
        finding.remediationLink('doc/arch_doc/remediation.md'),
        'doc/arch_doc/remediation.md#api003-internal-public-declarations',
      );
    });
  });
}
