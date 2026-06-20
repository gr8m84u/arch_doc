enum FindingSeverity { ok, observation, warning, error }

class FindingDefinition {
  final String code;
  final FindingSeverity severity;
  final String title;
  final String description;
  final String remediation;
  final String docsAnchor;
  final String configuration;

  const FindingDefinition({
    required this.code,
    required this.severity,
    required this.title,
    required this.description,
    required this.remediation,
    required this.docsAnchor,
    required this.configuration,
  });

  String get shortCode => code.split('_').first;
}

class FindingRegistry {
  static const packageLayerViolation = FindingDefinition(
    code: 'ARCH001_PACKAGE_LAYER_VIOLATION',
    severity: FindingSeverity.error,
    title: 'Package layer violation',
    description:
        'A package depends on another package from a forbidden architecture layer.',
    remediation:
        'Move the dependency behind an allowed abstraction, change the package layer assignment, or update the architecture rule if the dependency is intentional.',
    docsAnchor: 'arch001-package-layer-violation',
    configuration: 'rules',
  );

  static const duplicatePackageName = FindingDefinition(
    code: 'ARCH002_DUPLICATE_PACKAGE_NAME',
    severity: FindingSeverity.error,
    title: 'Duplicate package name',
    description:
        'Two different package directories use the same pubspec.yaml package name.',
    remediation:
        'Rename one package in pubspec.yaml or exclude one package path so generated reports can be indexed by package name safely.',
    docsAnchor: 'arch002-duplicate-package-name',
    configuration: 'excluded_packages, excluded_paths',
  );

  static const missingPublicEntrypoint = FindingDefinition(
    code: 'API001_MISSING_PUBLIC_ENTRYPOINT',
    severity: FindingSeverity.error,
    title: 'Missing public entrypoint',
    description:
        'The package does not expose a canonical lib/<package>.dart entrypoint.',
    remediation:
        'Create lib/<package>.dart, export the intended public API, and keep internal implementation under lib/src/.',
    docsAnchor: 'api001-missing-public-entrypoint',
    configuration: 'api_rules.require_public_entrypoint',
  );

  static const exportsFromSrc = FindingDefinition(
    code: 'API002_EXPORTS_FROM_SRC',
    severity: FindingSeverity.error,
    title: 'Exports from src',
    description:
        'The package public surface exports declarations from lib/src/**.',
    remediation:
        'Move public declarations outside lib/src/ or stop exporting implementation internals from the package entrypoint.',
    docsAnchor: 'api002-exports-from-src',
    configuration: 'api_rules.forbid_exports_from_src',
  );

  static const internalPublicDeclarations = FindingDefinition(
    code: 'API003_INTERNAL_PUBLIC_DECLARATIONS',
    severity: FindingSeverity.warning,
    title: 'Internal public declarations',
    description:
        'The package contains public declarations that are not exported by its public entrypoint.',
    remediation:
        'Export intended public declarations from lib/<package>.dart or make internal declarations private when they are implementation details.',
    docsAnchor: 'api003-internal-public-declarations',
    configuration: 'api_rules.warn_internal_public_declarations',
  );

  static const tooManyExportedSymbols = FindingDefinition(
    code: 'API004_TOO_MANY_EXPORTED_SYMBOLS',
    severity: FindingSeverity.warning,
    title: 'Too many exported symbols',
    description:
        'The package exports more symbols than the configured public API threshold.',
    remediation:
        'Review whether the package public API should be split, narrowed, or explicitly allowed by increasing the configured threshold.',
    docsAnchor: 'api004-too-many-exported-symbols',
    configuration: 'api_rules.max_exported_symbols_per_package',
  );

  static const apiWarning = FindingDefinition(
    code: 'API005_API_WARNING',
    severity: FindingSeverity.warning,
    title: 'API warning',
    description:
        'Public API analysis reported a package-specific warning that does not have a narrower finding code.',
    remediation:
        'Review the warning message, fix the exported file or parse issue, and rerun architecture generation.',
    docsAnchor: 'api005-api-warning',
    configuration: 'api_rules',
  );

  static const unknownResponsibility = FindingDefinition(
    code: 'COMP001_UNKNOWN_RESPONSIBILITY',
    severity: FindingSeverity.warning,
    title: 'Unknown responsibility',
    description:
        'Component discovery could not infer a clear responsibility from package metadata and public API names.',
    remediation:
        'Rename the package, improve its pubspec description, or expose clearer public API names so responsibility extraction can classify it.',
    docsAnchor: 'comp001-unknown-responsibility',
    configuration: 'component_rules.require_known_responsibility',
  );

  static const componentWithoutPublicApi = FindingDefinition(
    code: 'COMP002_COMPONENT_WITHOUT_PUBLIC_API',
    severity: FindingSeverity.warning,
    title: 'Component without public API',
    description:
        'A discovered component is backed by a package with no exported public API.',
    remediation:
        'Add the intended package entrypoint and exports, or exclude the package if it is not an architecture component.',
    docsAnchor: 'comp002-component-without-public-api',
    configuration: 'component_rules.warn_without_public_api',
  );

  static const componentWithoutDependents = FindingDefinition(
    code: 'COMP003_COMPONENT_WITHOUT_DEPENDENTS',
    severity: FindingSeverity.observation,
    title: 'No dependents detected in workspace',
    description:
        'No other discovered component in the workspace depends on this component.',
    remediation:
        'Review whether this is expected for an SDK entrypoint, externally consumed package, unused code, or a missing dependency edge.',
    docsAnchor: 'comp003-component-without-dependents',
    configuration: 'component_rules.warn_without_dependents',
  );

  static const componentWithoutDependencies = FindingDefinition(
    code: 'COMP004_COMPONENT_WITHOUT_DEPENDENCIES',
    severity: FindingSeverity.observation,
    title: 'No dependencies detected',
    description:
        'The component does not depend on any other discovered local component.',
    remediation:
        'Review whether this is an intended foundational component, standalone package, or whether dependency discovery missed a path/import.',
    docsAnchor: 'comp004-component-without-dependencies',
    configuration: 'component_rules.warn_without_dependencies',
  );

  static const externalPathNotFound = FindingDefinition(
    code: 'DISC001_EXTERNAL_PATH_NOT_FOUND',
    severity: FindingSeverity.warning,
    title: 'External path not found',
    description:
        'External filesystem package discovery found a path that does not exist or does not contain pubspec.yaml.',
    remediation:
        'Fix the path dependency, create the missing package, or disable external path package discovery if the path is intentionally unavailable.',
    docsAnchor: 'disc001-external-path-not-found',
    configuration: 'workspace_discovery.include_external_path_packages',
  );

  static const contractUnknownProtocol = FindingDefinition(
    code: 'CONTRACT001_UNKNOWN_PROTOCOL',
    severity: FindingSeverity.observation,
    title: 'Unknown contract protocol',
    description:
        'Contract analysis detected a contract but could not infer its protocol.',
    remediation:
        'Review the package name, type name, or source path and make the protocol explicit through naming if the contract should be classified.',
    docsAnchor: 'contract001-unknown-protocol',
    configuration: 'contract_analysis.detect_protocols',
  );

  static const contractConsumerUnknown = FindingDefinition(
    code: 'CONTRACT002_CONSUMER_UNKNOWN',
    severity: FindingSeverity.observation,
    title: 'Contract consumer unknown',
    description:
        'Contract analysis could not find a local consumer for a detected contract.',
    remediation:
        'Review whether the contract is intended for external SDK consumers or enable local references that make ownership visible.',
    docsAnchor: 'contract002-consumer-unknown',
    configuration: 'contract_analysis.warn_without_consumers',
  );

  static const contractProviderUnknown = FindingDefinition(
    code: 'CONTRACT003_PROVIDER_UNKNOWN',
    severity: FindingSeverity.warning,
    title: 'Contract provider unknown',
    description:
        'Contract analysis could not determine which component provides a contract.',
    remediation:
        'Ensure the contract declaration belongs to a discovered package/component or exclude incomplete package paths.',
    docsAnchor: 'contract003-provider-unknown',
    configuration: 'contract_analysis.enabled',
  );

  static const contractWithoutMethods = FindingDefinition(
    code: 'CONTRACT004_CONTRACT_WITHOUT_METHODS',
    severity: FindingSeverity.observation,
    title: 'Contract without methods',
    description:
        'A behavior contract has no public methods in v1 method extraction.',
    remediation:
        'Add public behavior methods if this is intended to be a behavior contract. If the type is a marker, data-only abstraction, constants holder, generated type, or domain/supporting type, classify or document it as supporting/domain/technical rather than fixing it as a missing-method contract.',
    docsAnchor: 'contract004-contract-without-methods',
    configuration: 'contract_analysis.include_lld_methods',
  );

  static const implementationWithoutExportedInterface = FindingDefinition(
    code: 'CONTRACT005_IMPLEMENTATION_WITHOUT_EXPORTED_INTERFACE',
    severity: FindingSeverity.warning,
    title: 'Implementation without exported interface',
    description:
        'A public class implements a type that was not detected as a component contract.',
    remediation:
        'Export or declare the intended interface as a public contract, or keep the implementation detail private.',
    docsAnchor: 'contract005-implementation-without-exported-interface',
    configuration: 'contract_analysis.enabled',
  );

  static const ambiguousContractName = FindingDefinition(
    code: 'CONTRACT007_AMBIGUOUS_CONTRACT_NAME',
    severity: FindingSeverity.observation,
    title: 'Ambiguous contract name',
    description: 'Contract name exists in multiple packages.',
    remediation:
        'Use explicit imports, avoid duplicate contract names, or configure package aliases if needed.',
    docsAnchor: 'contract007-ambiguous-contract-name',
    configuration: 'contract_analysis.enabled',
  );

  static const all = [
    packageLayerViolation,
    duplicatePackageName,
    missingPublicEntrypoint,
    exportsFromSrc,
    internalPublicDeclarations,
    tooManyExportedSymbols,
    apiWarning,
    unknownResponsibility,
    componentWithoutPublicApi,
    componentWithoutDependents,
    componentWithoutDependencies,
    externalPathNotFound,
    contractUnknownProtocol,
    contractConsumerUnknown,
    contractProviderUnknown,
    contractWithoutMethods,
    implementationWithoutExportedInterface,
    ambiguousContractName,
  ];

  static final Map<String, FindingDefinition> _byCode = {
    for (final definition in all) definition.code: definition,
  };

  static const Map<String, String> _ruleToCode = {
    'duplicate_package_name': 'ARCH002_DUPLICATE_PACKAGE_NAME',
    'require_public_entrypoint': 'API001_MISSING_PUBLIC_ENTRYPOINT',
    'forbid_exports_from_src': 'API002_EXPORTS_FROM_SRC',
    'warn_internal_public_declarations': 'API003_INTERNAL_PUBLIC_DECLARATIONS',
    'max_exported_symbols_per_package': 'API004_TOO_MANY_EXPORTED_SYMBOLS',
    'api_warning': 'API005_API_WARNING',
    'require_known_responsibility': 'COMP001_UNKNOWN_RESPONSIBILITY',
    'warn_without_public_api': 'COMP002_COMPONENT_WITHOUT_PUBLIC_API',
    'warn_without_dependents': 'COMP003_COMPONENT_WITHOUT_DEPENDENTS',
    'warn_without_dependencies': 'COMP004_COMPONENT_WITHOUT_DEPENDENCIES',
    'external_path_package_not_found': 'DISC001_EXTERNAL_PATH_NOT_FOUND',
    'contract_unknown_protocol': 'CONTRACT001_UNKNOWN_PROTOCOL',
    'contract_consumer_unknown': 'CONTRACT002_CONSUMER_UNKNOWN',
    'contract_provider_unknown': 'CONTRACT003_PROVIDER_UNKNOWN',
    'contract_without_methods': 'CONTRACT004_CONTRACT_WITHOUT_METHODS',
    'contract_implementation_without_exported_interface':
        'CONTRACT005_IMPLEMENTATION_WITHOUT_EXPORTED_INTERFACE',
    'contract_ambiguous_name': 'CONTRACT007_AMBIGUOUS_CONTRACT_NAME',
  };

  static FindingDefinition byCode(String code) {
    return _byCode[code] ?? packageLayerViolation;
  }

  static FindingDefinition forRule(String ruleName) {
    return byCode(_ruleToCode[ruleName] ?? packageLayerViolation.code);
  }
}
