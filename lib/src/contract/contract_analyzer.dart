import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../component/component_models.dart';
import '../config/arch_config.dart';
import '../validation/architecture_violation.dart';
import '../workspace/workspace_graph.dart';
import 'contract_models.dart';

class ContractAnalyzer {
  ComponentContractGraph analyze({
    required List<PackageNode> packages,
    required ComponentGraph componentGraph,
    required ArchConfig config,
  }) {
    if (!config.contractAnalysis.enabled) {
      return ComponentContractGraph(
        contracts: const [],
        consumedContracts: const [],
        implementedContracts: const [],
        findings: const [],
      );
    }

    final componentByPackage = {
      for (final component in componentGraph.components)
        component.packageName: component,
    };
    final packageInfos = <_PackageContractInfo>[];
    for (final package in packages) {
      final component = componentByPackage[package.name];
      if (component == null) continue;
      packageInfos.add(_analyzePackage(package, component, config));
    }

    final contracts = packageInfos.expand((info) => info.contracts).toList()
      ..sort(_compareContracts);
    final contractsByName = <String, List<ComponentContract>>{};
    for (final contract in contracts) {
      contractsByName
          .putIfAbsent(contract.interfaceName, () => [])
          .add(contract);
    }

    final consumed = <ConsumedContract>[];
    final implemented = <ImplementedContract>[];
    final ambiguityFindings = <ArchitectureViolation>[];

    for (final info in packageInfos) {
      final consumerNames = <String>{};
      for (final reference in info.references) {
        final contract = _resolveContract(
          reference.typeName,
          reference.imports,
          info.packageName,
          contractsByName,
          ambiguityFindings,
        );
        if (contract == null) continue;
        if (contract.sourcePackage == info.packageName) continue;
        consumed.add(
          ConsumedContract(
            contractName: contract.name,
            protocol: contract.protocol,
            providerComponent: contract.providerComponent,
            providerPackage: contract.sourcePackage,
            consumerComponent: info.componentName,
            usageEvidence: reference.typeName,
          ),
        );
        consumerNames.add(contract.name);
      }

      for (final implementation in info.implementations) {
        final contract = _resolveContract(
          implementation.interfaceName,
          implementation.imports,
          info.packageName,
          contractsByName,
          ambiguityFindings,
        );
        if (contract == null) {
          implemented.add(
            ImplementedContract(
              contractName: implementation.interfaceName,
              contractPackage: 'Unknown',
              definedBy: 'Unknown',
              implementationComponent: info.componentName,
              implementationClass: implementation.className,
              methodsImplemented: implementation.methodsImplemented,
            ),
          );
          continue;
        }
        implemented.add(
          ImplementedContract(
            contractName: contract.name,
            contractPackage: contract.sourcePackage,
            definedBy: contract.ownerComponent,
            implementationComponent: info.componentName,
            implementationClass: implementation.className,
            methodsImplemented: implementation.methodsImplemented,
          ),
        );
        consumerNames.add(contract.name);
      }

      if (consumerNames.isEmpty) {
        // Intentionally no finding here; SDK packages often expose contracts
        // for external consumers. CONTRACT002 is handled after consumer lists
        // are finalized and only when enabled in config.
      }
    }

    final consumersByContract = <String, Set<String>>{};
    for (final item in consumed) {
      final identity = '${item.providerPackage}:${item.contractName}';
      consumersByContract
          .putIfAbsent(identity, () => <String>{})
          .add(item.consumerComponent);
    }
    for (final item in implemented) {
      final identity = '${item.contractPackage}:${item.contractName}';
      consumersByContract
          .putIfAbsent(identity, () => <String>{})
          .add(item.implementationComponent);
    }

    final finalizedContracts = contracts.map((contract) {
      final consumers = consumersByContract[contract.identity]?.toList() ?? [];
      consumers.sort();
      return ComponentContract(
        name: contract.name,
        level: contract.level,
        protocol: contract.protocol,
        ownerComponent: contract.ownerComponent,
        providerComponent: contract.providerComponent,
        consumerComponents: consumers.isEmpty ? const ['Unknown'] : consumers,
        sourcePackage: contract.sourcePackage,
        sourcePath: contract.sourcePath,
        interfaceName: contract.interfaceName,
        endpointName: contract.endpointName,
        kind: contract.kind,
        methods: contract.methods,
      );
    }).toList()
      ..sort(_compareContracts);

    consumed.sort(_compareConsumed);
    implemented.sort(_compareImplemented);

    final findings = _buildFindings(finalizedContracts, implemented, config)
      ..addAll(_deduplicateAmbiguityFindings(ambiguityFindings))
      ..sort(_compareFindings);

    return ComponentContractGraph(
      contracts: finalizedContracts,
      consumedContracts: consumed,
      implementedContracts: implemented,
      findings: findings,
    );
  }

  ComponentContract? _resolveContract(
    String typeName,
    Set<String> imports,
    String currentPackage,
    Map<String, List<ComponentContract>> contractsByName,
    List<ArchitectureViolation> findings,
  ) {
    final candidates = contractsByName[typeName];
    if (candidates == null || candidates.isEmpty) return null;

    if (candidates.length == 1) return candidates.first;

    // Ambiguous case: try to match by package
    final importedPackages = imports
        .where((i) => i.startsWith('package:'))
        .map((i) => i.split('/')[0].replaceFirst('package:', ''))
        .toSet();

    final matches = candidates
        .where(
          (c) =>
              c.sourcePackage == currentPackage ||
              importedPackages.contains(c.sourcePackage),
        )
        .toList();

    if (matches.length == 1) return matches.first;

    // Still ambiguous
    findings.add(
      _finding(
        ruleName: 'contract_ambiguous_name',
        subject: typeName,
        reason:
            'Contract name `$typeName` exists in multiple packages; skipped ambiguous match.',
        level: ViolationLevel.observation,
      ),
    );

    return null;
  }

  List<ArchitectureViolation> _deduplicateAmbiguityFindings(
    List<ArchitectureViolation> findings,
  ) {
    final seen = <String>{};
    final result = <ArchitectureViolation>[];
    for (final finding in findings) {
      if (seen.add(finding.subject)) {
        result.add(finding);
      }
    }
    return result;
  }

  _PackageContractInfo _analyzePackage(
    PackageNode package,
    Component component,
    ArchConfig config,
  ) {
    final contracts = <ComponentContract>[];
    final references = <_ReferenceInfo>[];
    final implementations = <_ImplementationInfo>[];
    final libDir = Directory(p.join(package.rootPath, 'lib'));
    if (!libDir.existsSync()) {
      return _PackageContractInfo(
        packageName: package.name,
        componentName: component.name,
        contracts: contracts,
        references: references,
        implementations: implementations,
      );
    }

    final files = libDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !_isGenerated(file.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final sourcePath =
          p.relative(file.path, from: package.rootPath).replaceAll('\\', '/');
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;

      final imports = unit.directives
          .whereType<ImportDirective>()
          .map((d) => d.uri.stringValue)
          .whereType<String>()
          .toSet();

      for (final declaration
          in unit.declarations.whereType<ClassDeclaration>()) {
        final className = declaration.name.lexeme;
        if (_isPrivate(className)) continue;

        final typeRefs = _classPublicTypeReferences(declaration);
        for (final typeRef in typeRefs) {
          references.add(
            _ReferenceInfo(
              typeName: typeRef,
              imports: imports,
              sourcePath: sourcePath,
            ),
          );
        }

        final implementedInterfaces = _implementedInterfaces(declaration);
        if (implementedInterfaces.isNotEmpty) {
          implementations.add(
            _ImplementationInfo(
              className: className,
              interfaceName: implementedInterfaces.first,
              methodsImplemented: _publicMethodNames(declaration),
              imports: imports,
            ),
          );
        }

        if (!_isContractClass(declaration)) continue;

        final methods = config.contractAnalysis.includeLldMethods
            ? _methods(
                declaration,
                sourcePath,
                config.contractAnalysis.maxMethodsPerContract,
                unwrapTypes: config.contractAnalysis.unwrapAsyncTypes,
              )
            : <ContractMethod>[];
        final protocol = config.contractAnalysis.detectProtocols
            ? _protocol(
                packageName: package.name,
                typeName: className,
                sourcePath: sourcePath,
                isAbstract: _isAbstractLike(declaration),
              )
            : 'Unknown';

        contracts.add(
          ComponentContract(
            name: className,
            level: ContractLevel.hld,
            protocol: protocol,
            ownerComponent: component.name,
            providerComponent: component.name,
            consumerComponents: const ['Unknown'],
            sourcePackage: package.name,
            sourcePath: sourcePath,
            interfaceName: className,
            endpointName: className,
            kind: _contractKind(declaration),
            methods: methods,
          ),
        );
      }
    }

    contracts.sort(_compareContracts);
    implementations.sort((a, b) {
      final classCompare = a.className.compareTo(b.className);
      if (classCompare != 0) return classCompare;
      return a.interfaceName.compareTo(b.interfaceName);
    });

    return _PackageContractInfo(
      packageName: package.name,
      componentName: component.name,
      contracts: contracts,
      references: references,
      implementations: implementations,
    );
  }

  List<ArchitectureViolation> _buildFindings(
    List<ComponentContract> contracts,
    List<ImplementedContract> implemented,
    ArchConfig config,
  ) {
    final findings = <ArchitectureViolation>[];
    for (final contract in contracts) {
      if (contract.protocol == 'Unknown') {
        findings.add(
          _finding(
            ruleName: 'contract_unknown_protocol',
            subject: contract.name,
            reason: 'has unknown protocol.',
            level: ViolationLevel.observation,
          ),
        );
      }
      if (contract.providerComponent == 'Unknown') {
        findings.add(
          _finding(
            ruleName: 'contract_provider_unknown',
            subject: contract.name,
            reason: 'has unknown provider.',
            level: ViolationLevel.warning,
          ),
        );
      }
      if (contract.methods.isEmpty && contract.isBehaviorContract) {
        findings.add(
          _finding(
            ruleName: 'contract_without_methods',
            subject: contract.name,
            reason: 'has no detected public methods.',
            level: ViolationLevel.observation,
          ),
        );
      }
      if (config.contractAnalysis.warnWithoutConsumers &&
          contract.consumerComponents.contains('Unknown')) {
        findings.add(
          _finding(
            ruleName: 'contract_consumer_unknown',
            subject: contract.name,
            reason: 'has no detected local consumers.',
            level: ViolationLevel.observation,
          ),
        );
      }
    }

    for (final item in implemented) {
      if (item.definedBy == 'Unknown') {
        findings.add(
          _finding(
            ruleName: 'contract_implementation_without_exported_interface',
            subject: item.implementationClass,
            reason:
                'implements `${item.contractName}`, but that interface was not detected as an exported component contract.',
            level: ViolationLevel.warning,
          ),
        );
      }
    }

    return findings;
  }

  ArchitectureViolation _finding({
    required String ruleName,
    required String subject,
    required String reason,
    required ViolationLevel level,
  }) {
    return ArchitectureViolation(
      ruleName: ruleName,
      packageName: subject,
      dependencyName: 'N/A',
      reason: reason,
      level: level,
      category: 'contract',
      subject: subject,
      isRisk: level == ViolationLevel.warning,
    );
  }

  bool _isContractClass(ClassDeclaration declaration) {
    final name = declaration.name.lexeme;
    if (_isAbstractLike(declaration)) return true;
    return const [
      'Service',
      'Client',
      'Provider',
      'Repository',
      'Gateway',
      'Adapter',
    ].any(name.endsWith);
  }

  bool _isAbstractLike(ClassDeclaration declaration) {
    final source = declaration.toSource().trimLeft();
    return declaration.abstractKeyword != null ||
        source.startsWith('interface class ') ||
        source.startsWith('abstract interface class ');
  }

  String _contractKind(ClassDeclaration declaration) {
    final name = declaration.name.lexeme;
    if (_isInterfaceName(name)) return 'Interface';
    if (name.endsWith('Base')) return 'Base type';
    if (_isAbstractLike(declaration)) return 'Abstract class';
    for (final suffix in const [
      'Service',
      'Client',
      'Provider',
      'Repository',
      'Gateway',
      'Adapter',
    ]) {
      if (name.endsWith(suffix)) return suffix;
    }
    return 'Unknown';
  }

  bool _isInterfaceName(String name) {
    return (name.startsWith('I') &&
            name.length > 1 &&
            name[1].toUpperCase() == name[1]) ||
        name.endsWith('Interface');
  }

  String _protocol({
    required String packageName,
    required String typeName,
    required String sourcePath,
    required bool isAbstract,
  }) {
    final haystack = '$packageName $typeName $sourcePath'.toLowerCase();
    if (haystack.contains('grpc')) return 'gRPC';
    if (haystack.contains('shelf') || haystack.contains('http')) return 'HTTP';
    if (haystack.contains('named_pipe')) return 'Named Pipe';
    if (haystack.contains('ffi')) return 'FFI';
    if (isAbstract) return 'Dart API';
    return 'Unknown';
  }

  List<ContractMethod> _methods(
    ClassDeclaration declaration,
    String sourcePath,
    int maxMethods, {
    required bool unwrapTypes,
  }) {
    final methods = <ContractMethod>[];
    for (final member in declaration.members.whereType<MethodDeclaration>()) {
      final name = member.name.lexeme;
      if (_isPrivate(name) || member.isGetter || member.isSetter) continue;
      final returnInfo = _typeInfo(
        member.returnType?.toSource() ?? 'dynamic',
        unwrapTypes: unwrapTypes,
      );
      final requestTypes = <String>{};
      for (final parameter
          in member.parameters?.parameters ?? const <FormalParameter>[]) {
        final type = _parameterTypeSource(parameter);
        if (type != null && type.isNotEmpty) {
          requestTypes.add(_typeInfo(type, unwrapTypes: unwrapTypes).type);
        }
      }
      methods.add(
        ContractMethod(
          name: name,
          requestTypes: _sortedClean(requestTypes),
          responseTypes: _sortedClean({returnInfo.type}),
          errorTypes: _sortedRaw(returnInfo.errorTypes),
          sourcePath: sourcePath,
          signature: _methodSignature(member),
        ),
      );
      if (methods.length >= maxMethods) break;
    }
    methods.sort((a, b) => a.name.compareTo(b.name));
    return methods;
  }

  Set<String> _classPublicTypeReferences(ClassDeclaration declaration) {
    final references = <String>{};
    for (final member in declaration.members) {
      if (member is FieldDeclaration) {
        if (_isPrivate(member.fields.variables.first.name.lexeme)) continue;
        final type = member.fields.type?.toSource();
        if (type != null) references.add(_baseType(type));
      } else if (member is MethodDeclaration) {
        if (_isPrivate(member.name.lexeme)) continue;
        final returnType = member.returnType?.toSource();
        if (returnType != null) references.add(_baseType(returnType));
        for (final parameter
            in member.parameters?.parameters ?? const <FormalParameter>[]) {
          final type = _parameterTypeSource(parameter);
          if (type != null) references.add(_baseType(type));
        }
      } else if (member is ConstructorDeclaration) {
        if (member.name != null && _isPrivate(member.name!.lexeme)) continue;
        for (final parameter in member.parameters.parameters) {
          final type = _parameterTypeSource(parameter);
          if (type != null) references.add(_baseType(type));
        }
      }
    }
    references.removeWhere((type) => type.isEmpty || _isBuiltinType(type));
    return references;
  }

  List<String> _implementedInterfaces(ClassDeclaration declaration) {
    final names = <String>{};
    final extendsClause = declaration.extendsClause;
    if (extendsClause != null)
      names.add(_baseType(extendsClause.superclass.toSource()));
    final withClause = declaration.withClause;
    if (withClause != null) {
      for (final type in withClause.mixinTypes) {
        names.add(_baseType(type.toSource()));
      }
    }
    final implementsClause = declaration.implementsClause;
    if (implementsClause != null) {
      for (final type in implementsClause.interfaces) {
        names.add(_baseType(type.toSource()));
      }
    }
    names.removeWhere(
      (name) =>
          name.isEmpty || _isBuiltinType(name) || _isExternalBaseType(name),
    );
    return names.toList()..sort();
  }

  List<String> _publicMethodNames(ClassDeclaration declaration) {
    final names = declaration.members
        .whereType<MethodDeclaration>()
        .map((member) => member.name.lexeme)
        .where((name) => !_isPrivate(name))
        .toList()
      ..sort();
    return names;
  }

  String? _parameterTypeSource(FormalParameter parameter) {
    final source = parameter.toSource();
    final normalized = source
        .replaceAll(RegExp(r'\s*=\s*.*$'), '')
        .replaceAll(RegExp(r'\bthis\.'), '');
    final parts = normalized.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    return parts.first;
  }

  String _methodSignature(MethodDeclaration member) {
    final returnType = member.returnType?.toSource() ?? 'dynamic';
    final parameters =
        member.parameters?.parameters.map((p) => p.toSource()).join(', ') ?? '';
    return '$returnType ${member.name.lexeme}($parameters)';
  }

  _TypeInfo _typeInfo(String source, {required bool unwrapTypes}) {
    var type = source.trim();
    final errorTypes = <String>{};
    if (!unwrapTypes) return _TypeInfo(_baseType(type), errorTypes);
    var changed = true;
    while (changed) {
      changed = false;
      for (final wrapper in const ['Future', 'Stream', 'Result']) {
        final inner = _unwrap(type, wrapper);
        if (inner != null) {
          if (wrapper == 'Result') errorTypes.add('Result');
          type = inner;
          changed = true;
        }
      }
    }
    return _TypeInfo(_baseType(type), errorTypes);
  }

  String? _unwrap(String type, String wrapper) {
    final prefix = '$wrapper<';
    if (!type.startsWith(prefix) || !type.endsWith('>')) return null;
    return type.substring(prefix.length, type.length - 1).trim();
  }

  String _baseType(String source) {
    var type = source.trim();
    type = type.replaceAll('?', '');
    final genericIndex = type.indexOf('<');
    if (genericIndex != -1) {
      type = type.substring(0, genericIndex);
    }
    if (type.contains('.')) {
      type = type.split('.').last;
    }
    return type.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  }

  bool _isBuiltinType(String type) {
    return const {
      'void',
      'dynamic',
      'Object',
      'String',
      'int',
      'double',
      'num',
      'bool',
      'List',
      'Map',
      'Set',
      'Iterable',
      'Future',
      'Stream',
      'Result',
    }.contains(type);
  }

  bool _isExternalBaseType(String type) {
    return const {
      'GeneratedMessage',
      'ProtobufEnum',
      'Struct',
      'Exception',
      'Error',
      'Client',
      'Service',
    }.contains(type);
  }

  List<String> _sortedClean(Set<String> values) {
    final sorted = values
        .map(_baseType)
        .where((value) => value.isNotEmpty && !_isBuiltinType(value))
        .toSet()
        .toList()
      ..sort();
    return sorted.isEmpty ? const ['None'] : sorted;
  }

  List<String> _sortedRaw(Set<String> values) {
    final sorted = values.where((value) => value.isNotEmpty).toList()..sort();
    return sorted.isEmpty ? const ['None'] : sorted;
  }

  bool _isGenerated(String path) {
    final name = p.basename(path);
    return name.endsWith('.g.dart') ||
        name.endsWith('.freezed.dart') ||
        name.endsWith('.config.dart') ||
        path.replaceAll('\\', '/').contains('/generated/');
  }

  bool _isPrivate(String name) => name.startsWith('_');
}

class _PackageContractInfo {
  final String packageName;
  final String componentName;
  final List<ComponentContract> contracts;
  final List<_ReferenceInfo> references;
  final List<_ImplementationInfo> implementations;

  _PackageContractInfo({
    required this.packageName,
    required this.componentName,
    required this.contracts,
    required this.references,
    required this.implementations,
  });
}

class _ReferenceInfo {
  final String typeName;
  final Set<String> imports;
  final String sourcePath;

  _ReferenceInfo({
    required this.typeName,
    required this.imports,
    required this.sourcePath,
  });
}

class _ImplementationInfo {
  final String className;
  final String interfaceName;
  final List<String> methodsImplemented;
  final Set<String> imports;

  _ImplementationInfo({
    required this.className,
    required this.interfaceName,
    required this.methodsImplemented,
    required this.imports,
  });
}

class _TypeInfo {
  final String type;
  final Set<String> errorTypes;

  _TypeInfo(this.type, this.errorTypes);
}

int _compareContracts(ComponentContract a, ComponentContract b) {
  final owner = a.ownerComponent.compareTo(b.ownerComponent);
  if (owner != 0) return owner;
  return a.name.compareTo(b.name);
}

int _compareConsumed(ConsumedContract a, ConsumedContract b) {
  final consumer = a.consumerComponent.compareTo(b.consumerComponent);
  if (consumer != 0) return consumer;
  return a.contractName.compareTo(b.contractName);
}

int _compareImplemented(ImplementedContract a, ImplementedContract b) {
  final component = a.implementationComponent.compareTo(
    b.implementationComponent,
  );
  if (component != 0) return component;
  final className = a.implementationClass.compareTo(b.implementationClass);
  if (className != 0) return className;
  return a.contractName.compareTo(b.contractName);
}

int _compareFindings(ArchitectureViolation a, ArchitectureViolation b) {
  final code = a.code.compareTo(b.code);
  if (code != 0) return code;
  return a.subject.compareTo(b.subject);
}
