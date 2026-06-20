import 'package:test/test.dart';
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('RulesV2Validator', () {
    test('reports API rule findings', () {
      final findings = RulesV2Validator(
        config: ArchConfig(
          layers: {},
          rules: [],
          apiRules: ApiRulesConfig(
            requirePublicEntrypoint: true,
            forbidExportsFromSrc: true,
            warnInternalPublicDeclarations: true,
            maxExportedSymbolsPerPackage: 1,
          ),
          componentRules: ComponentRulesConfig(
            requireKnownResponsibility: false,
            warnWithoutPublicApi: false,
            warnWithoutDependents: false,
            warnWithoutDependencies: false,
          ),
        ),
        packageApis: {
          'pkg': PackageApi(
            packageName: 'pkg',
            description: '',
            publicSurface: [
              _declaration('A', 'src/a.dart'),
              _declaration('B', 'pkg.dart'),
            ],
            internalPublicDeclarations: [
              _declaration('Internal', 'src/internal.dart'),
            ],
            warnings: ['Missing public entrypoint `lib/pkg.dart`.'],
          ),
        },
        componentGraph: ComponentGraph(components: []),
      ).validate();

      expect(
        _rules(findings),
        containsAll([
          'require_public_entrypoint',
          'forbid_exports_from_src',
          'warn_internal_public_declarations',
          'max_exported_symbols_per_package',
        ]),
      );
      expect(
        findings
            .firstWhere(
              (finding) => finding.ruleName == 'require_public_entrypoint',
            )
            .level,
        ViolationLevel.error,
      );
      expect(
        findings
            .firstWhere(
              (finding) =>
                  finding.ruleName == 'warn_internal_public_declarations',
            )
            .level,
        ViolationLevel.warning,
      );
    });

    test('reports component rule findings', () {
      final findings = RulesV2Validator(
        config: ArchConfig(layers: {}, rules: []),
        packageApis: {},
        componentGraph: ComponentGraph(
          components: [
            Component(
              name: 'Unknown Component',
              packageName: 'pkg_unknown',
              responsibility: ResponsibilityExtractor.unknownResponsibility,
              dependencies: [],
              dependents: [],
              exportedSymbolCount: 0,
              keyExportedSymbols: [],
            ),
          ],
        ),
      ).validate();

      expect(
        _rules(findings),
        containsAll([
          'require_known_responsibility',
          'warn_without_public_api',
          'warn_without_dependents',
          'warn_without_dependencies',
        ]),
      );
      expect(
        findings
            .firstWhere(
              (finding) => finding.ruleName == 'require_known_responsibility',
            )
            .level,
        ViolationLevel.warning,
      );
      expect(
        findings
            .firstWhere(
              (finding) => finding.ruleName == 'warn_without_dependents',
            )
            .level,
        ViolationLevel.observation,
      );
    });

    test(
      'promotes risks, warnings, and observations according to risk policy',
      () {
        final baseComponent = Component(
          name: 'Unknown Component',
          packageName: 'pkg_unknown',
          responsibility: ResponsibilityExtractor.unknownResponsibility,
          dependencies: [],
          dependents: [],
          exportedSymbolCount: 1,
          keyExportedSymbols: [_declaration('A', 'pkg.dart')],
        );

        List<ArchitectureViolation> validate(RiskRulesConfig riskRules) {
          return RulesV2Validator(
            config: ArchConfig(layers: {}, rules: [], riskRules: riskRules),
            packageApis: {},
            componentGraph: ComponentGraph(components: [baseComponent]),
          ).validate();
        }

        expect(
          validate(
            RiskRulesConfig(
              failOnRisks: true,
              failOnWarnings: false,
              failOnObservations: false,
            ),
          )
              .firstWhere(
                (finding) => finding.ruleName == 'require_known_responsibility',
              )
              .level,
          ViolationLevel.error,
        );
        expect(
          validate(
            RiskRulesConfig(
              failOnRisks: false,
              failOnWarnings: true,
              failOnObservations: false,
            ),
          )
              .firstWhere(
                (finding) => finding.ruleName == 'require_known_responsibility',
              )
              .level,
          ViolationLevel.error,
        );
        expect(
          validate(
            RiskRulesConfig(
              failOnRisks: false,
              failOnWarnings: false,
              failOnObservations: true,
            ),
          )
              .firstWhere(
                (finding) => finding.ruleName == 'warn_without_dependents',
              )
              .level,
          ViolationLevel.error,
        );
      },
    );

    test('sorts findings deterministically', () {
      final findings = [
        ArchitectureViolation(
          ruleName: 'z',
          packageName: 'pkg',
          dependencyName: 'N/A',
          reason: 'z reason',
          level: ViolationLevel.observation,
          category: 'component',
          subject: 'Z',
        ),
        ArchitectureViolation(
          ruleName: 'a',
          packageName: 'pkg',
          dependencyName: 'N/A',
          reason: 'a reason',
          level: ViolationLevel.error,
          category: 'api',
          subject: 'A',
        ),
        ArchitectureViolation(
          ruleName: 'b',
          packageName: 'pkg',
          dependencyName: 'N/A',
          reason: 'b reason',
          level: ViolationLevel.warning,
          category: 'api',
          subject: 'B',
        ),
      ]..sort(compareFindings);

      expect(findings.map((finding) => finding.level), [
        ViolationLevel.error,
        ViolationLevel.warning,
        ViolationLevel.observation,
      ]);
    });
  });
}

List<String> _rules(List<ArchitectureViolation> findings) {
  return findings.map((finding) => finding.ruleName).toList();
}

ApiDeclaration _declaration(String name, String libraryPath) {
  return ApiDeclaration(
    name: name,
    kind: ApiDeclarationKind.classDeclaration,
    libraryPath: libraryPath,
  );
}
