import '../component/component_models.dart';
import '../config/arch_config.dart';
import 'contract_diagram_generator.dart';
import 'contract_models.dart';

class ContractMarkdownGenerator {
  final ComponentContractGraph graph;
  final ComponentGraph componentGraph;
  final ArchConfig config;

  ContractMarkdownGenerator({
    required this.graph,
    required this.componentGraph,
    required this.config,
  });

  String generateGlobal(String diagramContent, String plantUmlLink) {
    final buffer = StringBuffer();
    final behaviorContracts = graph.contracts
        .where((contract) => contract.isBehaviorContract)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final supportingDomainTypes = graph.contracts
        .where((contract) => contract.isSupportingDomainType)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final technicalTypes = graph.contracts
        .where((contract) => contract.isTechnicalOrGeneratedType)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final concreteTypes = graph.contracts
        .where((contract) => contract.isContractLikeConcreteClass)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Component Contracts');
    buffer.writeln();
    buffer.writeln('## Contract health');
    buffer.writeln();
    buffer.writeln('| Metric | Count |');
    buffer.writeln('| --- | ---: |');
    buffer.writeln('| Behavior contracts | ${behaviorContracts.length} |');
    buffer.writeln(
      '| Supporting/domain types | ${supportingDomainTypes.length} |',
    );
    buffer.writeln('| Technical/generated types | ${technicalTypes.length} |');
    buffer.writeln(
      '| Contract-like concrete classes | ${concreteTypes.length} |',
    );
    buffer.writeln(
      '| Protocol not detected | ${graph.protocolNotDetectedCount} |',
    );
    buffer.writeln(
      '| Provider not detected | ${graph.providerNotDetectedCount} |',
    );
    buffer.writeln(
      '| Contracts without detected consumers | ${graph.notDetectedInWorkspaceConsumerCount} |',
    );
    buffer.writeln(
      '| Implementation warnings | ${graph.implementationWarningCount} |',
    );
    buffer.writeln();

    _writeDiagram(buffer, diagramContent, './contracts.mmd', plantUmlLink);

    buffer.writeln('## Behavior Contracts');
    buffer.writeln();
    _writeContractTable(buffer, behaviorContracts, './remediation.md');

    buffer.writeln('## Supporting / Domain Types');
    buffer.writeln();
    _writeContractTable(buffer, supportingDomainTypes, './remediation.md');

    buffer.writeln('## Technical / Generated Types');
    buffer.writeln();
    _writeContractTable(buffer, technicalTypes, './remediation.md');

    buffer.writeln('## Contract-Like Concrete Classes');
    buffer.writeln();
    _writeContractTable(buffer, concreteTypes, './remediation.md');

    buffer.writeln('## Consumed contracts');
    buffer.writeln();
    _writeConsumedTable(buffer, graph.consumedContracts);

    buffer.writeln('## Implemented contracts');
    buffer.writeln();
    _writeImplementedTable(buffer, graph.implementedContracts);

    return buffer.toString();
  }

  String generateComponent(
    Component component,
    String hldDiagramContent,
    String hldDiagramFileName,
    String hldPlantUmlFileName,
    String lldDiagramContent,
    String lldDiagramFileName,
    String lldPlantUmlFileName,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Component: ${component.name}');
    buffer.writeln();
    buffer.writeln('## Responsibility');
    buffer.writeln();
    buffer.writeln(component.responsibility);
    buffer.writeln();

    final ownedContracts = graph.contracts
        .where((contract) => contract.ownerComponent == component.name)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final provided = ownedContracts.where((c) => c.isBehaviorContract).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final consumed = graph.consumedContracts
        .where(
          (contract) =>
              contract.consumerComponent == component.name &&
              contract.providerComponent != component.name &&
              _isBehaviorContractReference(
                contract.contractName,
                contract.providerPackage,
              ),
        )
        .toList()
      ..sort((a, b) => a.contractName.compareTo(b.contractName));
    final implemented = graph.implementedContracts
        .where(
          (contract) =>
              contract.implementationComponent == component.name &&
              _isBehaviorContractReference(
                contract.contractName,
                contract.contractPackage,
              ),
        )
        .toList()
      ..sort((a, b) => a.contractName.compareTo(b.contractName));
    final externalConsumers = _externalConsumersFor(provided, component.name);
    final hldRelationships = _hldRelationshipsFor(component.name, provided);
    final externalProviders = _externalProvidersFor(
      consumed: consumed,
      implemented: implemented,
      currentComponent: component.name,
    );
    final supportingTypes = _supportingTypesFor(ownedContracts);
    final diagramGenerator = ContractDiagramGenerator(
      graph,
      config: config.contractDiagrams,
    );

    buffer.writeln('## HLD: Component contracts');
    buffer.writeln();
    _writeDiagram(
      buffer,
      hldDiagramContent,
      './$hldDiagramFileName',
      './$hldPlantUmlFileName',
    );
    buffer.writeln(
      '- HLD shows components/packages and contract-labeled relationships.',
    );
    buffer.writeln(
      '- HLD diagrams do not include interfaces, classes, methods, request models, or response models as nodes.',
    );
    if (hldDiagramContent.contains('depends on API')) {
      buffer.writeln(
        '- `depends on API` is shown when a component both consumes and implements contracts from the same provider component.',
      );
    }
    buffer.writeln();

    buffer.writeln('### HLD Summary');
    buffer.writeln();
    buffer.writeln(
      '| Behavior contracts | Consumed contracts | External consumers | External providers |',
    );
    buffer.writeln('| ---: | ---: | ---: | ---: |');
    buffer.writeln(
      '| ${provided.length} | ${consumed.length} | ${externalConsumers.length} | ${externalProviders.length} |',
    );
    buffer.writeln();

    buffer.writeln('### HLD Relationships');
    buffer.writeln();
    _writeHldRelationshipsTable(buffer, hldRelationships);

    buffer.writeln('### Provided contracts');
    buffer.writeln();
    _writeContractTable(
      buffer,
      provided,
      '../remediation.md',
      currentComponent: component.name,
    );

    buffer.writeln('### Contracts consumed from other components');
    buffer.writeln();
    _writeConsumedTable(buffer, consumed);

    buffer.writeln('## LLD: Contract details');
    buffer.writeln();
    if (config.contractDiagrams.lldGranularity == 'component' ||
        config.contractDiagrams.includeComponentLldOverview) {
      _writeDiagram(
        buffer,
        lldDiagramContent,
        './$lldDiagramFileName',
        './$lldPlantUmlFileName',
      );
    }
    buffer.writeln(
      '- LLD shows interfaces, implementation classes, direct request/response models, and method details.',
    );
    buffer.writeln('- Supporting types are not recursively expanded.');
    buffer.writeln();

    buffer.writeln('### Implemented contracts');
    buffer.writeln();
    _writeImplementedTable(buffer, implemented);

    buffer.writeln('### Implemented external contracts');
    buffer.writeln();
    _writeImplementedExternalReferences(buffer, implemented, component.name);

    buffer.writeln('### Supporting Types');
    buffer.writeln();
    _writeSupportingTypes(buffer, supportingTypes);

    buffer.writeln('### Low-level contract details');
    buffer.writeln();
    if (provided.isEmpty) {
      _writeExternalContractDetailsNote(buffer, implemented, component.name);
    } else {
      for (final contract in provided) {
        buffer.writeln('### ${contract.name}');
        buffer.writeln();
        if (config.contractDiagrams.perContractLld) {
          _writeInlineMermaid(
            buffer,
            diagramGenerator.generateForContractLld(component, contract),
          );
        }
        _writeMethodTable(buffer, contract);
      }
    }

    return buffer.toString();
  }

  void _writeDiagram(
    StringBuffer buffer,
    String diagramContent,
    String link,
    String plantUmlLink,
  ) {
    if (config.diagramEmbedding.inlineMermaid) {
      buffer.writeln('```mermaid');
      buffer.write(diagramContent.trimRight());
      buffer.writeln();
      buffer.writeln('```');
      buffer.writeln();
      buffer.writeln('PlantUML: [Open diagram]($plantUmlLink)');
    } else {
      buffer.writeln('Mermaid: [Open diagram]($link)');
      buffer.writeln();
      buffer.writeln('PlantUML: [Open diagram]($plantUmlLink)');
    }
    buffer.writeln();
  }

  void _writeInlineMermaid(StringBuffer buffer, String diagramContent) {
    buffer.writeln('```mermaid');
    buffer.write(diagramContent.trimRight());
    buffer.writeln();
    buffer.writeln('```');
    buffer.writeln();
  }

  void _writeHldRelationshipsTable(
    StringBuffer buffer,
    List<_HldRelationship> relationships,
  ) {
    if (relationships.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    buffer.writeln('| Relationship | Component | Contracts |');
    buffer.writeln('| --- | --- | --- |');
    for (final relationship in relationships) {
      buffer.writeln(
        '| ${relationship.relationship} | ${relationship.component} | ${_formatList(relationship.contracts)} |',
      );
    }
    buffer.writeln();
  }

  void _writeContractTable(
    StringBuffer buffer,
    List<ComponentContract> contracts,
    String remediationPath, {
    String? currentComponent,
  }) {
    if (contracts.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    final includeActionColumns = contracts.any(
      (contract) =>
          contract.protocol == 'Unknown' ||
          contract.providerComponent == 'Unknown',
    );
    if (currentComponent == null) {
      if (includeActionColumns) {
        buffer.writeln(
          '| Severity | Protocol | Contract kind | Contract | Provider | Consumers | Methods | Remediation |',
        );
        buffer.writeln('| --- | --- | --- | --- | --- | --- | ---: | --- |');
      } else {
        buffer.writeln(
          '| Protocol | Contract kind | Contract | Provider | Consumers | Methods |',
        );
        buffer.writeln('| --- | --- | --- | --- | --- | ---: |');
      }
    } else {
      if (includeActionColumns) {
        buffer.writeln(
          '| Severity | Protocol | Contract kind | Contract | Provider | External consumers | Internal usage | Methods | Remediation |',
        );
        buffer.writeln(
          '| --- | --- | --- | --- | --- | --- | --- | ---: | --- |',
        );
      } else {
        buffer.writeln(
          '| Protocol | Contract kind | Contract | Provider | External consumers | Internal usage | Methods |',
        );
        buffer.writeln('| --- | --- | --- | --- | --- | --- | ---: |');
      }
    }
    for (final contract in contracts) {
      final severity = contract.protocol == 'Unknown' ? 'Observation' : 'OK';
      final remediation = contract.protocol == 'Unknown'
          ? '[How to fix]($remediationPath#contract001-unknown-protocol)'
          : 'None';
      final methodCount = _filterContractMethods(contract.methods).length;
      if (currentComponent == null) {
        if (includeActionColumns) {
          buffer.writeln(
            '| $severity | ${contract.protocol} | ${contract.kind} | `${contract.name}` | ${contract.providerComponent} | ${_formatList(contract.consumerComponents)} | $methodCount | $remediation |',
          );
        } else {
          buffer.writeln(
            '| ${contract.protocol} | ${contract.kind} | `${contract.name}` | ${contract.providerComponent} | ${_formatList(contract.consumerComponents)} | $methodCount |',
          );
        }
      } else {
        final externalConsumers = _externalConsumers(
          contract,
          currentComponent,
        );
        final internalUsage =
            contract.consumerComponents.contains(currentComponent)
                ? 'Yes'
                : 'No';
        if (includeActionColumns) {
          buffer.writeln(
            '| $severity | ${contract.protocol} | ${contract.kind} | `${contract.name}` | ${contract.providerComponent} | ${_formatList(externalConsumers)} | $internalUsage | $methodCount | $remediation |',
          );
        } else {
          buffer.writeln(
            '| ${contract.protocol} | ${contract.kind} | `${contract.name}` | ${contract.providerComponent} | ${_formatList(externalConsumers)} | $internalUsage | $methodCount |',
          );
        }
      }
    }
    buffer.writeln();
  }

  void _writeConsumedTable(
    StringBuffer buffer,
    List<ConsumedContract> contracts,
  ) {
    if (contracts.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    buffer.writeln(
      '| Protocol | Contract | Provider | Consumer | Usage evidence |',
    );
    buffer.writeln('| --- | --- | --- | --- | --- |');
    for (final contract in contracts) {
      buffer.writeln(
        '| ${contract.protocol} | `${contract.contractName}` | ${contract.providerComponent} | ${contract.consumerComponent} | `${contract.usageEvidence}` |',
      );
    }
    buffer.writeln();
  }

  void _writeImplementedTable(
    StringBuffer buffer,
    List<ImplementedContract> contracts,
  ) {
    if (contracts.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    buffer.writeln(
      '| Contract | Defined by | Implementation class | Methods implemented |',
    );
    buffer.writeln('| --- | --- | --- | --- |');
    for (final contract in contracts) {
      final methods = _filterMethodNames(contract.methodsImplemented);
      buffer.writeln(
        '| `${contract.contractName}` | ${contract.definedBy} | `${contract.implementationClass}` | ${_formatList(methods)} |',
      );
    }
    buffer.writeln();
  }

  void _writeImplementedExternalReferences(
    StringBuffer buffer,
    List<ImplementedContract> contracts,
    String currentComponent,
  ) {
    final external = contracts
        .where(
          (contract) =>
              contract.definedBy != 'Unknown' &&
              contract.definedBy != currentComponent,
        )
        .toList()
      ..sort((a, b) {
        final definedBy = a.definedBy.compareTo(b.definedBy);
        if (definedBy != 0) return definedBy;
        return a.contractName.compareTo(b.contractName);
      });
    if (external.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }

    buffer.writeln('| Contract | Defined by | See |');
    buffer.writeln('| --- | --- | --- |');
    for (final contract in external) {
      final link = _componentContractLink(
        contract.definedBy,
        contract.contractName,
      );
      buffer.writeln(
        '| `${contract.contractName}` | ${contract.definedBy} | [Open contract]($link) |',
      );
    }
    buffer.writeln();
  }

  void _writeExternalContractDetailsNote(
    StringBuffer buffer,
    List<ImplementedContract> contracts,
    String currentComponent,
  ) {
    final external = _externalImplementedContracts(contracts, currentComponent);
    if (external.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }

    buffer.writeln(
      'This component implements external contracts. Contract method details are documented in the provider component pages.',
    );
    buffer.writeln();
    buffer.writeln('| Contract | Defined by | Details |');
    buffer.writeln('| --- | --- | --- |');
    for (final contract in external) {
      final link = _componentContractLink(
        contract.definedBy,
        contract.contractName,
      );
      buffer.writeln(
        '| `${contract.contractName}` | ${contract.definedBy} | [Open contract]($link) |',
      );
    }
    buffer.writeln();
  }

  List<ImplementedContract> _externalImplementedContracts(
    List<ImplementedContract> contracts,
    String currentComponent,
  ) {
    return contracts
        .where(
          (contract) =>
              contract.definedBy != 'Unknown' &&
              contract.definedBy != currentComponent,
        )
        .toList()
      ..sort((a, b) {
        final definedBy = a.definedBy.compareTo(b.definedBy);
        if (definedBy != 0) return definedBy;
        return a.contractName.compareTo(b.contractName);
      });
  }

  void _writeMethodTable(StringBuffer buffer, ComponentContract contract) {
    final filteredMethods = _filterContractMethods(contract.methods);
    if (filteredMethods.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    buffer.writeln(
      '| Method | Signature | Request models | Response models | Error/result models |',
    );
    buffer.writeln('| --- | --- | --- | --- | --- |');
    for (final method in filteredMethods) {
      buffer.writeln(
        '| `${method.name}` | `${method.signature}` | ${_formatList(method.requestTypes)} | ${_formatList(method.responseTypes)} | ${_formatList(method.errorTypes)} |',
      );
    }
    buffer.writeln();
  }

  void _writeSupportingTypes(StringBuffer buffer, List<String> types) {
    if (types.isEmpty) {
      buffer.writeln('None detected.');
      buffer.writeln();
      return;
    }
    for (final type in types) {
      buffer.writeln('- `$type`');
    }
    buffer.writeln();
  }

  List<_HldRelationship> _hldRelationshipsFor(
    String currentComponent,
    List<ComponentContract> provided,
  ) {
    final providedIdentities =
        provided.map((contract) => contract.identity).toSet();
    final relationships = <String, _HldRelationship>{};

    void add(String relationship, String component, String contractName) {
      if (component == 'Unknown' || component == currentComponent) return;
      final key = '$relationship\n$component';
      relationships
          .putIfAbsent(
            key,
            () => _HldRelationship(
              relationship: relationship,
              component: component,
              contracts: <String>{},
            ),
          )
          .contracts
          .add(contractName);
    }

    for (final contract in provided) {
      for (final consumer in contract.consumerComponents) {
        add('Consumed by', consumer, contract.name);
      }
    }
    for (final contract in graph.consumedContracts) {
      final identity = '${contract.providerPackage}:${contract.contractName}';
      if (providedIdentities.contains(identity)) {
        add('Consumed by', contract.consumerComponent, contract.contractName);
      }
      if (contract.consumerComponent == currentComponent &&
          _isBehaviorContractReference(
            contract.contractName,
            contract.providerPackage,
          )) {
        add('Consumed from', contract.providerComponent, contract.contractName);
      }
    }
    for (final contract in graph.implementedContracts) {
      final identity = '${contract.contractPackage}:${contract.contractName}';
      if (providedIdentities.contains(identity)) {
        add(
          'Implemented by',
          contract.implementationComponent,
          contract.contractName,
        );
      }
      if (contract.implementationComponent == currentComponent &&
          _isBehaviorContractReference(
            contract.contractName,
            contract.contractPackage,
          )) {
        add('Implemented for', contract.definedBy, contract.contractName);
      }
    }

    final result = relationships.values.toList()
      ..sort((a, b) {
        final order = _relationshipOrder(
          a.relationship,
        ).compareTo(_relationshipOrder(b.relationship));
        if (order != 0) return order;
        return a.component.compareTo(b.component);
      });
    for (final relationship in result) {
      relationship.sortContracts();
    }
    return result;
  }

  Set<String> _externalProvidersFor({
    required List<ConsumedContract> consumed,
    required List<ImplementedContract> implemented,
    required String currentComponent,
  }) {
    return {
      for (final contract in consumed)
        if (contract.providerComponent != 'Unknown' &&
            contract.providerComponent != currentComponent)
          contract.providerComponent,
      for (final contract in implemented)
        if (contract.definedBy != 'Unknown' &&
            contract.definedBy != currentComponent)
          contract.definedBy,
    };
  }

  List<String> _supportingTypesFor(List<ComponentContract> contracts) {
    final behaviorContracts =
        contracts.where((contract) => contract.isBehaviorContract).toList();
    final supportingTypes = {
      for (final contract in behaviorContracts)
        for (final method in contract.methods) ...[
          ...method.requestTypes.where((type) => type != 'None'),
          ...method.responseTypes.where((type) => type != 'None'),
        ],
    };
    final ownedNoMethodContracts = contracts
        .where((contract) => contract.isSupportingDomainType)
        .map((contract) => contract.name);
    for (final name in ownedNoMethodContracts) {
      if (supportingTypes.contains(name)) supportingTypes.add(name);
    }
    return supportingTypes.toList()..sort();
  }

  List<String> _externalConsumers(
    ComponentContract contract,
    String currentComponent,
  ) {
    final consumers = contract.consumerComponents
        .where(
          (consumer) => consumer != 'Unknown' && consumer != currentComponent,
        )
        .toSet()
        .toList()
      ..sort();
    return consumers;
  }

  Set<String> _externalConsumersFor(
    List<ComponentContract> contracts,
    String currentComponent,
  ) {
    return {
      for (final contract in contracts)
        ..._externalConsumers(contract, currentComponent),
    };
  }

  List<String> _filterMethodNames(List<String> names) {
    var filtered = names.where(
      (name) =>
          !const {'==', 'hashCode', 'toString', 'runtimeType'}.contains(name),
    );

    if (!config.contractAnalysis.includeGeneratedMethods) {
      filtered = filtered.where((name) {
        if (name.endsWith('_Pre')) return false;
        if (name.startsWith(r'$')) return false;
        if (name.startsWith('_')) return false;
        return true;
      });
    }

    return filtered.toList()..sort();
  }

  List<ContractMethod> _filterContractMethods(List<ContractMethod> methods) {
    var filtered = methods.where(
      (m) =>
          !const {'==', 'hashCode', 'toString', 'runtimeType'}.contains(m.name),
    );

    if (!config.contractAnalysis.includeGeneratedMethods) {
      filtered = filtered.where((m) {
        if (m.name.endsWith('_Pre')) return false;
        if (m.name.startsWith(r'$')) return false;
        if (m.name.startsWith('_')) return false;
        return true;
      });
    }

    return filtered.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  String _formatList(Iterable<String> values) {
    if (values.isEmpty) return 'None';
    final sorted = values.toList()..sort();
    return sorted.map((value) => '`$value`').join(', ');
  }

  bool _isBehaviorContractReference(String name, String packageName) {
    for (final contract in graph.contracts) {
      if (contract.name == name &&
          (packageName == 'Unknown' || contract.sourcePackage == packageName)) {
        return contract.isBehaviorContract;
      }
    }
    return true;
  }

  String _componentContractLink(String componentName, String contractName) {
    final slug = _componentSlugFor(componentName);
    return './$slug.md#${_anchor(contractName)}';
  }

  String _componentSlugFor(String componentName) {
    for (final component in componentGraph.components) {
      if (component.name == componentName) {
        return componentContractSlug(component);
      }
    }
    return componentName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _anchor(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  int _relationshipOrder(String relationship) {
    switch (relationship) {
      case 'Consumed by':
        return 0;
      case 'Consumed from':
        return 1;
      case 'Implemented by':
        return 2;
      case 'Implemented for':
        return 3;
      default:
        return 4;
    }
  }
}

class _HldRelationship {
  final String relationship;
  final String component;
  final Set<String> contracts;

  _HldRelationship({
    required this.relationship,
    required this.component,
    required this.contracts,
  });

  void sortContracts() {
    final sorted = contracts.toList()..sort();
    contracts
      ..clear()
      ..addAll(sorted);
  }
}

String componentContractSlug(Component component) {
  return component.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class ComponentContractDocumentSet {
  final String globalMarkdown;
  final String globalMermaid;
  final String globalPlantUml;
  final Map<String, String> componentMarkdownBySlug;
  final Map<String, String> componentHldMermaidBySlug;
  final Map<String, String> componentHldPlantUmlBySlug;
  final Map<String, String> componentLldMermaidBySlug;
  final Map<String, String> componentLldPlantUmlBySlug;

  ComponentContractDocumentSet({
    required this.globalMarkdown,
    required this.globalMermaid,
    required this.globalPlantUml,
    required this.componentMarkdownBySlug,
    required this.componentHldMermaidBySlug,
    required this.componentHldPlantUmlBySlug,
    required this.componentLldMermaidBySlug,
    required this.componentLldPlantUmlBySlug,
  });
}

ComponentContractDocumentSet generateContractDocuments({
  required ComponentContractGraph graph,
  required ComponentGraph componentGraph,
  required ArchConfig config,
}) {
  final diagramGenerator = ContractDiagramGenerator(
    graph,
    config: config.contractDiagrams,
  );
  final markdownGenerator = ContractMarkdownGenerator(
    graph: graph,
    componentGraph: componentGraph,
    config: config,
  );
  final globalMermaid = diagramGenerator.generateGlobal();
  final globalPlantUml = diagramGenerator.generateGlobalPlantUml();
  final components = componentGraph.components.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final componentMarkdown = <String, String>{};
  final componentHldMermaid = <String, String>{};
  final componentHldPlantUml = <String, String>{};
  final componentLldMermaid = <String, String>{};
  final componentLldPlantUml = <String, String>{};
  for (final component in components) {
    final slug = componentContractSlug(component);
    final hldMermaid = diagramGenerator.generateForComponentHld(component);
    final lldMermaid = diagramGenerator.generateForComponentLld(component);
    final hldPlantUml = diagramGenerator.generateForComponentHldPlantUml(
      component,
    );
    final lldPlantUml = diagramGenerator.generateForComponentLldPlantUml(
      component,
    );
    componentHldMermaid[slug] = hldMermaid;
    componentLldMermaid[slug] = lldMermaid;
    componentHldPlantUml[slug] = hldPlantUml;
    componentLldPlantUml[slug] = lldPlantUml;
    componentMarkdown[slug] = markdownGenerator.generateComponent(
      component,
      hldMermaid,
      '$slug.hld.mmd',
      '$slug.hld.puml',
      lldMermaid,
      '$slug.lld.mmd',
      '$slug.lld.puml',
    );
  }
  return ComponentContractDocumentSet(
    globalMarkdown: markdownGenerator.generateGlobal(
      globalMermaid,
      './${config.output.contractsDiagramPlantUml}',
    ),
    globalMermaid: globalMermaid,
    globalPlantUml: globalPlantUml,
    componentMarkdownBySlug: componentMarkdown,
    componentHldMermaidBySlug: componentHldMermaid,
    componentHldPlantUmlBySlug: componentHldPlantUml,
    componentLldMermaidBySlug: componentLldMermaid,
    componentLldPlantUmlBySlug: componentLldPlantUml,
  );
}
