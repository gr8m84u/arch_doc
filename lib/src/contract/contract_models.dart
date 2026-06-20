import '../validation/architecture_violation.dart';

enum ContractLevel { hld, lld }

class ComponentContract {
  final String name;
  final ContractLevel level;
  final String protocol;
  final String ownerComponent;
  final String providerComponent;
  final List<String> consumerComponents;
  final String sourcePackage;
  final String sourcePath;
  final String interfaceName;
  final String endpointName;
  final String kind;
  final List<ContractMethod> methods;

  ComponentContract({
    required this.name,
    required this.level,
    required this.protocol,
    required this.ownerComponent,
    required this.providerComponent,
    required this.consumerComponents,
    required this.sourcePackage,
    required this.sourcePath,
    required this.interfaceName,
    required this.endpointName,
    required this.kind,
    required this.methods,
  });

  String get identity => '$sourcePackage:$interfaceName';

  bool get isInterfaceLike {
    if (name.startsWith('I') &&
        name.length > 1 &&
        name[1].toUpperCase() == name[1]) {
      return true;
    }
    if (name.endsWith('Interface')) return true;
    return false;
  }

  bool get isExplicitBehaviorBase {
    return const [
      'ServiceBase',
      'ClientBase',
      'ProviderBase',
      'RepositoryBase',
      'GatewayBase',
      'AdapterBase',
    ].any(name.endsWith);
  }

  bool get isBehaviorContract {
    if (isGeneratedSourceType) return false;
    if (isExplicitBehaviorBase) return true;
    if (isInterfaceLike && methods.isNotEmpty) return true;
    if (kind == 'Abstract class' && methods.isNotEmpty) return true;
    return false;
  }

  bool get isSupportingDomainType {
    return isInterfaceLike && methods.isEmpty && !isExplicitBehaviorBase;
  }

  bool get isContractLikeConcreteClass {
    return const [
      'Service',
      'Client',
      'Provider',
      'Repository',
      'Gateway',
      'Adapter',
    ].contains(kind);
  }

  bool get isTechnicalOrGeneratedType {
    if (isGeneratedSourceType) return true;
    if (isBehaviorContract || isSupportingDomainType) return false;
    if (kind == 'Base type') return true;
    if (name.endsWith('ServiceBase')) return true;
    if (methods.isEmpty &&
        (name.endsWith('Defaults') ||
            name.endsWith('Keys') ||
            name.endsWith('Names') ||
            name.endsWith('Values') ||
            name.endsWith('Codes') ||
            name.endsWith('JsonKeys'))) {
      return true;
    }
    return methods.isEmpty && kind == 'Abstract class';
  }

  bool get isGeneratedSourceType {
    final normalized = sourcePath.replaceAll('\\', '/');
    return normalized.endsWith('.g.dart') ||
        normalized.endsWith('.pb.dart') ||
        normalized.endsWith('.pbenum.dart') ||
        normalized.endsWith('.pbgrpc.dart') ||
        normalized.endsWith('.pbjson.dart');
  }
}

class ContractMethod {
  final String name;
  final List<String> requestTypes;
  final List<String> responseTypes;
  final List<String> errorTypes;
  final String sourcePath;
  final String signature;

  ContractMethod({
    required this.name,
    required this.requestTypes,
    required this.responseTypes,
    required this.errorTypes,
    required this.sourcePath,
    required this.signature,
  });
}

class ConsumedContract {
  final String contractName;
  final String protocol;
  final String providerComponent;
  final String providerPackage;
  final String consumerComponent;
  final String usageEvidence;

  ConsumedContract({
    required this.contractName,
    required this.protocol,
    required this.providerComponent,
    required this.providerPackage,
    required this.consumerComponent,
    required this.usageEvidence,
  });
}

class ImplementedContract {
  final String contractName;
  final String contractPackage;
  final String definedBy;
  final String implementationComponent;
  final String implementationClass;
  final List<String> methodsImplemented;

  ImplementedContract({
    required this.contractName,
    required this.contractPackage,
    required this.definedBy,
    required this.implementationComponent,
    required this.implementationClass,
    required this.methodsImplemented,
  });
}

class ComponentContractGraph {
  final List<ComponentContract> contracts;
  final List<ConsumedContract> consumedContracts;
  final List<ImplementedContract> implementedContracts;
  final List<ArchitectureViolation> findings;

  ComponentContractGraph({
    required this.contracts,
    required this.consumedContracts,
    required this.implementedContracts,
    required this.findings,
  });

  int get protocolNotDetectedCount =>
      contracts.where((contract) => contract.protocol == 'Unknown').length;

  int get providerNotDetectedCount => contracts
      .where((contract) => contract.providerComponent == 'Unknown')
      .length;

  int get notDetectedInWorkspaceConsumerCount => contracts
      .where((contract) => contract.consumerComponents.contains('Unknown'))
      .length;

  int get implementationWarningCount => findings
      .where(
        (finding) =>
            finding.code ==
            'CONTRACT005_IMPLEMENTATION_WITHOUT_EXPORTED_INTERFACE',
      )
      .length;
}
