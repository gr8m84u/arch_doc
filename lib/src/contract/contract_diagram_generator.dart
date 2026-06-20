import '../component/component_models.dart';
import '../config/arch_config.dart';
import '../diagram/diagram_graph.dart';
import '../diagram/mermaid_renderer.dart';
import '../diagram/plantuml_renderer.dart';
import 'contract_models.dart';

class ContractDiagramGenerator {
  final ComponentContractGraph graph;
  final ContractDiagramsConfig config;

  ContractDiagramGenerator(this.graph, {ContractDiagramsConfig? config})
      : config = config ?? ContractDiagramsConfig.defaults();

  String generateGlobal() {
    if (config.layered) {
      return config.componentView
          ? _generateGlobalLayeredComponent()
          : _generateGlobalLayeredType();
    }
    return _generateGlobalAuto();
  }

  String generateGlobalPlantUml() {
    return PlantUmlRenderer().render(buildGlobalGraph());
  }

  String generateForComponent(Component component) {
    if (config.layered) {
      return generateForComponentLld(component);
    }
    return _generateForComponentAuto(component);
  }

  String generateForComponentHld(Component component) {
    return MermaidRenderer().render(buildForComponentHldGraph(component));
  }

  String generateForComponentHldPlantUml(Component component) {
    return PlantUmlRenderer().render(buildForComponentHldGraph(component));
  }

  DiagramGraph buildForComponentHldGraph(Component component) {
    final provided = _behaviorContractsFor(component.name)
      ..sort(_compareContracts);
    final providedIdentities =
        provided.map((contract) => contract.identity).toSet();

    final incomingUses = <String, Set<String>>{};
    for (final contract in provided) {
      for (final consumer in contract.consumerComponents) {
        if (consumer == 'Unknown' || consumer == component.name) continue;
        incomingUses.putIfAbsent(consumer, () => <String>{}).add(contract.name);
      }
    }
    for (final item in graph.consumedContracts) {
      final identity = '${item.providerPackage}:${item.contractName}';
      if (!providedIdentities.contains(identity)) continue;
      if (item.consumerComponent == 'Unknown' ||
          item.consumerComponent == component.name) {
        continue;
      }
      incomingUses
          .putIfAbsent(item.consumerComponent, () => <String>{})
          .add(item.contractName);
    }

    final incomingImplements = <String, Set<String>>{};
    for (final item in graph.implementedContracts) {
      final identity = '${item.contractPackage}:${item.contractName}';
      if (!providedIdentities.contains(identity)) continue;
      if (item.implementationComponent == 'Unknown' ||
          item.implementationComponent == component.name) {
        continue;
      }
      incomingImplements
          .putIfAbsent(item.implementationComponent, () => <String>{})
          .add(item.contractName);
    }

    final outgoingUses = <String, Set<String>>{};
    final consumedExternal = graph.consumedContracts.toList()
      ..sort(_compareConsumedContracts);
    for (final item in consumedExternal) {
      if (item.consumerComponent != component.name) continue;
      if (!_isBehaviorContractReference(
        item.contractName,
        item.providerPackage,
      )) {
        continue;
      }
      if (item.providerComponent == 'Unknown' ||
          item.providerComponent == component.name) {
        continue;
      }
      outgoingUses
          .putIfAbsent(item.providerComponent, () => <String>{})
          .add(item.contractName);
    }

    final outgoingImplements = <String, Set<String>>{};
    for (final item in graph.implementedContracts.toList()
      ..sort(_compareImplementedContracts)) {
      if (item.implementationComponent != component.name) continue;
      if (!_isBehaviorContractReference(
        item.contractName,
        item.contractPackage,
      )) {
        continue;
      }
      if (item.definedBy == 'Unknown' || item.definedBy == component.name) {
        continue;
      }
      outgoingImplements
          .putIfAbsent(item.definedBy, () => <String>{})
          .add(item.contractName);
    }

    final componentNames = <String>{
      component.name,
      ...incomingUses.keys,
      ...incomingImplements.keys,
      ...outgoingUses.keys,
      ...outgoingImplements.keys,
    }.toList()
      ..sort();

    final currentId = _componentId(component.name);
    final edges = <DiagramEdge>[
      for (final entry in incomingUses.entries)
        DiagramEdge(
          from: _componentId(entry.key),
          to: currentId,
          label: _hldUsesLabel(entry.value, incomingImplements[entry.key]),
        ),
      for (final entry in incomingImplements.entries)
        DiagramEdge(
          from: _componentId(entry.key),
          to: currentId,
          label: _contractListLabel('implements', entry.value),
        ),
      for (final entry in outgoingUses.entries)
        DiagramEdge(
          from: currentId,
          to: _componentId(entry.key),
          label: _hldUsesLabel(entry.value, outgoingImplements[entry.key]),
        ),
      for (final entry in outgoingImplements.entries)
        DiagramEdge(
          from: currentId,
          to: _componentId(entry.key),
          label: _contractListLabel('implements', entry.value),
        ),
    ]..sort(_compareDiagramEdges);

    return DiagramGraph(
      direction: 'LR',
      groups: [
        DiagramGroup(
          title: 'Components',
          nodes: [
            for (final name in componentNames)
              DiagramNode(
                id: _componentId(name),
                label: name,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
      ],
      edges: edges,
    );
  }

  DiagramGraph buildForContractLldGraph(
    Component component,
    ComponentContract contract,
  ) {
    final implementations = graph.implementedContracts
        .where(
          (item) =>
              item.contractName == contract.name &&
              item.contractPackage == contract.sourcePackage &&
              item.implementationComponent != 'Unknown',
        )
        .toList()
      ..sort(_compareImplementedContracts);
    final requestTypes = <String>{
      for (final method in contract.methods)
        ...method.requestTypes.where((type) => type != 'None'),
    }.toList()
      ..sort();
    final responseTypes = <String>{
      for (final method in contract.methods)
        ...method.responseTypes.where((type) => type != 'None'),
    }.toList()
      ..sort();

    final contractId = _contractId(contract);
    final edges = <DiagramEdge>[
      for (final type in requestTypes)
        DiagramEdge(
          from: _supportingTypeId(type),
          to: contractId,
          label: 'request',
        ),
      for (final type in responseTypes)
        DiagramEdge(
          from: contractId,
          to: _supportingTypeId(type),
          label: 'response',
        ),
      for (final item in implementations)
        DiagramEdge(
          from: _implementationId(item),
          to: contractId,
          label: 'implements',
        ),
    ]..sort(_compareDiagramEdges);

    return DiagramGraph(
      direction: 'LR',
      groups: [
        DiagramGroup(
          title: 'Request Types',
          nodes: [
            for (final type in requestTypes)
              DiagramNode(
                id: _supportingTypeId(type),
                label: type,
                kind: DiagramNodeKind.model,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Contract',
          nodes: [
            DiagramNode(
              id: contractId,
              label: contract.name,
              kind: DiagramNodeKind.interfaceType,
            ),
          ],
        ),
        DiagramGroup(
          title: 'Response Types',
          nodes: [
            for (final type in responseTypes)
              DiagramNode(
                id: _supportingTypeId(type),
                label: type,
                kind: DiagramNodeKind.model,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Implementations',
          nodes: [
            for (final item in implementations)
              DiagramNode(
                id: _implementationId(item),
                label: item.implementationClass,
                kind: DiagramNodeKind.classType,
              ),
          ],
        ),
      ],
      edges: edges,
    );
  }

  String generateForContractLld(
    Component component,
    ComponentContract contract,
  ) {
    return MermaidRenderer().render(
      buildForContractLldGraph(component, contract),
    );
  }

  String generateForComponentLld(Component component) {
    return MermaidRenderer().render(buildForComponentLldGraph(component));
  }

  String generateForComponentLldPlantUml(Component component) {
    return PlantUmlRenderer().render(buildForComponentLldGraph(component));
  }

  DiagramGraph buildGlobalGraph() {
    if (config.layered) {
      return config.componentView
          ? _buildGlobalLayeredComponentGraph()
          : _buildGlobalLayeredTypeGraph();
    }
    return _buildGlobalAutoGraph();
  }

  DiagramGraph _buildGlobalAutoGraph() {
    final contracts = _behaviorContracts()..sort(_compareContracts);
    final nodesById = <String, DiagramNode>{};
    final edges = <DiagramEdge>[];
    for (final contract in contracts) {
      final contractId = _contractId(contract);
      nodesById[contractId] = DiagramNode(
        id: contractId,
        label: contract.name,
        kind: DiagramNodeKind.contract,
      );
      final providerId = _componentId(contract.providerComponent);
      nodesById[providerId] = DiagramNode(
        id: providerId,
        label: contract.providerComponent,
        kind: DiagramNodeKind.component,
      );
      edges.add(
        DiagramEdge(from: providerId, to: contractId, label: 'provides'),
      );
      for (final consumer in contract.consumerComponents.where(
        (c) => c != 'Unknown',
      )) {
        final consumerId = _componentId(consumer);
        nodesById[consumerId] = DiagramNode(
          id: consumerId,
          label: consumer,
          kind: DiagramNodeKind.component,
        );
        edges.add(DiagramEdge(from: consumerId, to: contractId, label: 'uses'));
      }
    }
    return DiagramGraph(
      direction: 'TD',
      groups: [
        DiagramGroup(title: 'Contracts', nodes: nodesById.values.toList()),
      ],
      edges: edges,
    );
  }

  DiagramGraph _buildGlobalLayeredTypeGraph() {
    final contracts = _behaviorContracts()..sort(_compareContracts);
    final contractIdentities = contracts.map((c) => c.identity).toSet();
    final implementations = graph.implementedContracts
        .where(
          (item) => contractIdentities.contains(
            '${item.contractPackage}:${item.contractName}',
          ),
        )
        .toList()
      ..sort(_compareImplementedContracts);
    final consumers = [
      ...graph.consumedContracts
          .where(
            (contract) => contractIdentities.contains(
              '${contract.providerPackage}:${contract.contractName}',
            ),
          )
          .map((contract) => contract.consumerComponent),
      ...contracts.expand((contract) => contract.consumerComponents),
    ].where((consumer) => consumer != 'Unknown').toSet().toList()
      ..sort();

    final edges = <DiagramEdge>[
      for (final item in implementations)
        if (item.contractPackage != 'Unknown')
          DiagramEdge(
            from: _contractIdByIdentity(
              '${item.contractPackage}:${item.contractName}',
            ),
            to: _implementationId(item),
            label: 'implemented by',
          ),
      for (final item
          in graph.consumedContracts.toList()..sort(_compareConsumedContracts))
        if (item.consumerComponent != 'Unknown' &&
            item.providerPackage != 'Unknown' &&
            contractIdentities.contains(
              '${item.providerPackage}:${item.contractName}',
            ))
          DiagramEdge(
            from: _componentId(item.consumerComponent),
            to: _contractIdByIdentity(
              '${item.providerPackage}:${item.contractName}',
            ),
            label: 'uses',
          ),
      for (final contract in contracts)
        for (final consumer in contract.consumerComponents.where(
          (consumer) => consumer != 'Unknown',
        ))
          DiagramEdge(
            from: _componentId(consumer),
            to: _contractId(contract),
            label: 'uses',
          ),
    ];

    return DiagramGraph(
      direction: 'TD',
      groups: [
        DiagramGroup(
          title: 'Contracts',
          nodes: [
            for (final contract in contracts)
              DiagramNode(
                id: _contractId(contract),
                label: contract.name,
                kind: DiagramNodeKind.interfaceType,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Implementations',
          nodes: [
            for (final item in implementations)
              DiagramNode(
                id: _implementationId(item),
                label: item.implementationClass,
                kind: DiagramNodeKind.classType,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Consumers',
          nodes: [
            for (final consumer in consumers)
              DiagramNode(
                id: _componentId(consumer),
                label: consumer,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
      ],
      edges: edges,
    );
  }

  DiagramGraph _buildGlobalLayeredComponentGraph() {
    final contracts = _behaviorContracts()..sort(_compareContracts);
    final contractIdentities = contracts.map((c) => c.identity).toSet();
    final implementations = graph.implementedContracts
        .where(
          (item) => contractIdentities.contains(
            '${item.contractPackage}:${item.contractName}',
          ),
        )
        .toList()
      ..sort(_compareImplementedContracts);
    final consumers = [
      ...graph.consumedContracts
          .where(
            (contract) => contractIdentities.contains(
              '${contract.providerPackage}:${contract.contractName}',
            ),
          )
          .map((contract) => contract.consumerComponent),
      ...contracts.expand((contract) => contract.consumerComponents),
    ].where((consumer) => consumer != 'Unknown').toSet().toList()
      ..sort();
    final contractComponents = contracts
        .map((contract) => contract.providerComponent)
        .where((component) => component != 'Unknown')
        .toSet()
        .toList()
      ..sort();
    final implementationComponents = implementations
        .map((item) => item.implementationComponent)
        .where((component) => component != 'Unknown')
        .toSet()
        .toList()
      ..sort();

    return DiagramGraph(
      direction: 'TD',
      groups: [
        DiagramGroup(
          title: 'Contracts',
          nodes: [
            for (final component in contractComponents)
              DiagramNode(
                id: _contractComponentId(component),
                label: component,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Implementations',
          nodes: [
            for (final component in implementationComponents)
              DiagramNode(
                id: _implementationComponentId(component),
                label: component,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Consumers',
          nodes: [
            for (final consumer in consumers)
              DiagramNode(
                id: _consumerId(consumer),
                label: consumer,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
      ],
      edges: [
        for (final edge in _componentEdges(
          contracts,
          implementations,
          graph.consumedContracts
              .where(
                (contract) => contractIdentities.contains(
                  '${contract.providerPackage}:${contract.contractName}',
                ),
              )
              .toList(),
        ))
          DiagramEdge(from: edge.from, to: edge.to, label: edge.label),
      ],
    );
  }

  String _generateGlobalAuto() {
    final buffer = StringBuffer();
    buffer.writeln('flowchart TD');
    final contracts = _behaviorContracts()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final contract in contracts) {
      final contractId = _contractId(contract);
      buffer.writeln('  $contractId["${_escape(contract.name)}"]');
      buffer.writeln(
        '  ${_componentId(contract.providerComponent)}["${_escape(contract.providerComponent)}"]',
      );
      buffer.writeln(
        '  ${_componentId(contract.providerComponent)} -->|provides| $contractId',
      );
      for (final consumer in contract.consumerComponents.where(
        (c) => c != 'Unknown',
      )) {
        buffer.writeln('  ${_consumerId(consumer)}["${_escape(consumer)}"]');
        buffer.writeln('  ${_consumerId(consumer)} -->|uses| $contractId');
      }
    }
    return buffer.toString();
  }

  String _generateForComponentAuto(Component component) {
    final buffer = StringBuffer();
    buffer.writeln('flowchart TD');
    final componentId = _componentId(component.name);
    buffer.writeln('  $componentId["${_escape(component.name)}"]');

    final provided = graph.contracts
        .where((contract) => contract.ownerComponent == component.name)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final contract in provided) {
      final contractId = _contractId(contract);
      buffer.writeln('  $contractId["${_escape(contract.name)}"]');
      buffer.writeln('  $componentId -->|provides| $contractId');
      for (final consumer in contract.consumerComponents.where(
        (c) => c != 'Unknown',
      )) {
        final consumerId = _consumerId(consumer);
        buffer.writeln('  $consumerId["${_escape(consumer)}"]');
        buffer.writeln('  $consumerId -->|uses| $contractId');
      }
      final modelNames = contract.methods
          .expand(
            (method) => [...method.requestTypes, ...method.responseTypes],
          )
          .where((type) => type != 'None')
          .toSet()
          .toList()
        ..sort();
      if (modelNames.isNotEmpty) {
        final modelId = '${contractId}_models';
        buffer.writeln('  $modelId["${_escape(modelNames.join(' / '))}"]');
        buffer.writeln('  $contractId -->|request/response| $modelId');
      }
    }

    final implemented = graph.implementedContracts
        .where((item) => item.implementationComponent == component.name)
        .toList()
      ..sort((a, b) => a.contractName.compareTo(b.contractName));
    for (final item in implemented) {
      if (item.contractPackage == 'Unknown') continue;
      final contractId = _contractIdByIdentity(
        '${item.contractPackage}:${item.contractName}',
      );
      buffer.writeln('  $contractId["${_escape(item.contractName)}"]');
      buffer.writeln('  $componentId -->|implements| $contractId');
    }

    final consumed = graph.consumedContracts
        .where((item) => item.consumerComponent == component.name)
        .toList()
      ..sort((a, b) => a.contractName.compareTo(b.contractName));
    for (final item in consumed) {
      if (item.providerPackage == 'Unknown') continue;
      final contractId = _contractIdByIdentity(
        '${item.providerPackage}:${item.contractName}',
      );
      final providerId = _componentId(item.providerComponent);
      buffer.writeln('  $contractId["${_escape(item.contractName)}"]');
      buffer.writeln('  $providerId["${_escape(item.providerComponent)}"]');
      buffer.writeln('  $componentId -->|uses| $contractId');
      buffer.writeln('  $providerId -->|provides| $contractId');
    }

    return buffer.toString();
  }

  String _generateGlobalLayeredType() {
    final contracts = _behaviorContracts()..sort(_compareContracts);
    final contractIdentities = contracts.map((c) => c.identity).toSet();
    final implementations = graph.implementedContracts
        .where(
          (item) => contractIdentities.contains(
            '${item.contractPackage}:${item.contractName}',
          ),
        )
        .toList()
      ..sort(_compareImplementedContracts);
    final consumers = [
      ...graph.consumedContracts
          .where(
            (contract) => contractIdentities.contains(
              '${contract.providerPackage}:${contract.contractName}',
            ),
          )
          .map((contract) => contract.consumerComponent),
      ...contracts.expand((contract) => contract.consumerComponents),
    ].where((consumer) => consumer != 'Unknown').toSet().toList()
      ..sort();

    final contractNodes = [
      for (final contract in contracts)
        _Node(_contractId(contract), contract.name),
    ];
    final implementationNodes = [
      for (final item in implementations)
        _Node(_implementationId(item), item.implementationClass),
    ];
    final consumerNodes = [
      for (final consumer in consumers) _Node(_componentId(consumer), consumer),
    ];
    final edges = <_Edge>[
      for (final item in implementations)
        if (item.contractPackage != 'Unknown')
          _Edge(
            _contractIdByIdentity(
              '${item.contractPackage}:${item.contractName}',
            ),
            _implementationId(item),
            'implemented by',
          ),
      for (final item
          in graph.consumedContracts.toList()..sort(_compareConsumedContracts))
        if (item.consumerComponent != 'Unknown' &&
            item.providerPackage != 'Unknown' &&
            contractIdentities.contains(
              '${item.providerPackage}:${item.contractName}',
            ))
          _Edge(
            _componentId(item.consumerComponent),
            _contractIdByIdentity(
              '${item.providerPackage}:${item.contractName}',
            ),
            'uses',
          ),
      for (final contract in contracts)
        for (final consumer in contract.consumerComponents.where(
          (consumer) => consumer != 'Unknown',
        ))
          _Edge(_componentId(consumer), _contractId(contract), 'uses'),
    ]..sort(_compareEdges);

    return _renderLayered(
      contracts: contractNodes,
      implementations: implementationNodes,
      consumers: consumerNodes,
      edges: edges,
    );
  }

  String _generateGlobalLayeredComponent() {
    final contracts = _behaviorContracts()..sort(_compareContracts);
    final contractIdentities = contracts.map((c) => c.identity).toSet();
    final implementations = graph.implementedContracts
        .where(
          (item) => contractIdentities.contains(
            '${item.contractPackage}:${item.contractName}',
          ),
        )
        .toList()
      ..sort(_compareImplementedContracts);
    final consumers = [
      ...graph.consumedContracts
          .where(
            (contract) => contractIdentities.contains(
              '${contract.providerPackage}:${contract.contractName}',
            ),
          )
          .map((contract) => contract.consumerComponent),
      ...contracts.expand((contract) => contract.consumerComponents),
    ].where((consumer) => consumer != 'Unknown').toSet().toList()
      ..sort();

    final contractComponents = contracts
        .map((contract) => contract.providerComponent)
        .where((component) => component != 'Unknown')
        .toSet()
        .toList()
      ..sort();
    final implementationComponents = implementations
        .map((item) => item.implementationComponent)
        .where((component) => component != 'Unknown')
        .toSet()
        .toList()
      ..sort();

    return _renderLayered(
      contracts: [
        for (final component in contractComponents)
          _Node(_contractComponentId(component), component),
      ],
      implementations: [
        for (final component in implementationComponents)
          _Node(_implementationComponentId(component), component),
      ],
      consumers: [
        for (final consumer in consumers)
          _Node(_consumerId(consumer), consumer),
      ],
      edges: _componentEdges(
        contracts,
        implementations,
        graph.consumedContracts
            .where(
              (contract) => contractIdentities.contains(
                '${contract.providerPackage}:${contract.contractName}',
              ),
            )
            .toList(),
      ),
    );
  }

  DiagramGraph buildForComponentLldGraph(Component component) {
    final ownedContracts = graph.contracts
        .where((contract) => contract.ownerComponent == component.name)
        .toList()
      ..sort(_compareContracts);
    final behaviorContracts = _behaviorContractsFor(component.name)
      ..sort(_compareContracts);
    final behaviorContractIdentities =
        behaviorContracts.map((contract) => contract.identity).toSet();

    final consumed = graph.consumedContracts
        .where(
          (item) =>
              item.consumerComponent != 'Unknown' &&
              item.consumerComponent != component.name &&
              behaviorContractIdentities.contains(
                '${item.providerPackage}:${item.contractName}',
              ),
        )
        .toList()
      ..sort(_compareConsumedContracts);
    final implementations = graph.implementedContracts
        .where(
          (item) =>
              behaviorContractIdentities.contains(
                '${item.contractPackage}:${item.contractName}',
              ) &&
              item.implementationComponent != 'Unknown',
        )
        .toList()
      ..sort(_compareImplementedContracts);

    final consumers = [
      ...consumed.map((item) => item.consumerComponent),
      ...behaviorContracts.expand(
        (contract) => contract.consumerComponents,
      ),
    ]
        .where(
          (consumer) => consumer != 'Unknown' && consumer != component.name,
        )
        .toSet()
        .toList()
      ..sort();
    final implementationComponents = implementations
        .map((item) => item.implementationComponent)
        .toSet()
        .toList()
      ..sort();

    final supportingTypeNames = _supportingTypesFor(behaviorContracts);
    final ownedSupportingContracts = ownedContracts
        .where(_isSupportingDomainType)
        .map((contract) => contract.name)
        .where((name) => supportingTypeNames.contains(name))
        .toSet();
    final supportingTypes = {
      ...supportingTypeNames,
      ...ownedSupportingContracts,
    }.toList()
      ..sort();

    final edges = <DiagramEdge>[
      for (final item in consumed)
        DiagramEdge(
          from: _componentId(item.consumerComponent),
          to: _contractIdByIdentity(
            '${item.providerPackage}:${item.contractName}',
          ),
          label: 'uses',
        ),
      for (final contract in behaviorContracts)
        for (final consumer in contract.consumerComponents.where(
          (consumer) => consumer != 'Unknown' && consumer != component.name,
        ))
          DiagramEdge(
            from: _componentId(consumer),
            to: _contractId(contract),
            label: 'uses',
          ),
      for (final contract in behaviorContracts)
        for (final method in contract.methods)
          for (final requestType in method.requestTypes.where(
            (type) => type != 'None',
          ))
            DiagramEdge(
              from: _supportingTypeId(requestType),
              to: _contractId(contract),
              label: 'request',
            ),
      for (final contract in behaviorContracts)
        for (final method in contract.methods)
          for (final responseType in method.responseTypes.where(
            (type) => type != 'None',
          ))
            DiagramEdge(
              from: _contractId(contract),
              to: _supportingTypeId(responseType),
              label: 'response',
            ),
      for (final item in implementations)
        DiagramEdge(
          from: _implementationComponentId(item.implementationComponent),
          to: _contractIdByIdentity(
            '${item.contractPackage}:${item.contractName}',
          ),
          label: 'implements',
        ),
      for (final item in implementations)
        DiagramEdge(
          from: _implementationId(item),
          to: _implementationComponentId(item.implementationComponent),
          label: 'class',
        ),
    ]..sort(_compareDiagramEdges);

    return DiagramGraph(
      direction: 'LR',
      groups: [
        DiagramGroup(
          title: 'Consumers',
          nodes: [
            for (final consumer in consumers)
              DiagramNode(
                id: _componentId(consumer),
                label: consumer,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Contracts',
          nodes: [
            for (final contract in behaviorContracts)
              DiagramNode(
                id: _contractId(contract),
                label: contract.name,
                kind: DiagramNodeKind.interfaceType,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Supporting Types',
          nodes: [
            for (final type in supportingTypes)
              DiagramNode(
                id: _supportingTypeId(type),
                label: type,
                kind: DiagramNodeKind.model,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Implementation Components',
          nodes: [
            for (final component in implementationComponents)
              DiagramNode(
                id: _implementationComponentId(component),
                label: component,
                kind: DiagramNodeKind.component,
              ),
          ],
        ),
        DiagramGroup(
          title: 'Implementations',
          nodes: [
            for (final item in implementations)
              DiagramNode(
                id: _implementationId(item),
                label: item.implementationClass,
                kind: DiagramNodeKind.classType,
              ),
          ],
        ),
      ],
      edges: edges,
    );
  }

  String _renderLayered({
    String contractsTitle = 'Contracts',
    required List<_Node> contracts,
    required List<_Node> implementations,
    required List<_Node> consumers,
    required List<_Edge> edges,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('flowchart TD');
    _writeSubgraph(buffer, contractsTitle, contracts);
    _writeSubgraph(buffer, 'Implementations', implementations);
    _writeSubgraph(buffer, 'Consumers', consumers);
    final uniqueEdges = <String, _Edge>{};
    for (final edge in edges) {
      uniqueEdges['${edge.from}\n${edge.to}\n${edge.label}'] = edge;
    }
    final sortedEdges = uniqueEdges.values.toList()..sort(_compareEdges);
    for (final edge in sortedEdges) {
      buffer.writeln('  ${edge.from} -->|${_escape(edge.label)}| ${edge.to}');
    }
    return buffer.toString();
  }

  void _writeSubgraph(StringBuffer buffer, String title, List<_Node> nodes) {
    final uniqueNodes = <String, _Node>{};
    for (final node in nodes) {
      uniqueNodes[node.id] = node;
    }
    final sorted = uniqueNodes.values.toList()..sort(_compareNodes);
    if (sorted.isEmpty) return;
    buffer.writeln('  subgraph $title');
    for (final node in sorted) {
      buffer.writeln('    ${node.id}["${_escape(node.label)}"]');
    }
    buffer.writeln('  end');
  }

  List<_Edge> _componentEdges(
    List<ComponentContract> contracts,
    List<ImplementedContract> implementations,
    List<ConsumedContract> consumed, {
    String? excludedConsumer,
  }) {
    final implementedCounts = <String, int>{};
    for (final item in implementations) {
      if (item.contractPackage == 'Unknown') continue;
      final key = '${item.definedBy}\n${item.implementationComponent}';
      implementedCounts[key] = (implementedCounts[key] ?? 0) + 1;
    }

    final consumedCounts = <String, Set<String>>{};
    for (final item in consumed) {
      if (item.providerPackage == 'Unknown' ||
          item.consumerComponent == 'Unknown') {
        continue;
      }
      final key = '${item.consumerComponent}\n${item.providerComponent}';
      consumedCounts.putIfAbsent(key, () => <String>{}).add(item.contractName);
    }
    for (final contract in contracts) {
      if (contract.providerComponent == 'Unknown') continue;
      for (final consumer in contract.consumerComponents) {
        if (consumer == 'Unknown') continue;
        if (consumer == excludedConsumer) continue;
        final key = '$consumer\n${contract.providerComponent}';
        consumedCounts.putIfAbsent(key, () => <String>{}).add(contract.name);
      }
    }

    return [
      for (final entry in implementedCounts.entries)
        _countedEdge(
          _contractComponentId(entry.key.split('\n').first),
          _implementationComponentId(entry.key.split('\n').last),
          'implemented by',
          entry.value,
        ),
      for (final entry in consumedCounts.entries)
        _countedEdge(
          _consumerId(entry.key.split('\n').first),
          _contractComponentId(entry.key.split('\n').last),
          'uses',
          entry.value.length,
        ),
    ]..sort(_compareEdges);
  }

  _Edge _countedEdge(String from, String to, String action, int count) {
    final suffix = count == 1 ? '1 contract' : '$count contracts';
    return _Edge(from, to, '$action $suffix');
  }

  String _componentId(String value) => 'component_${_id(value)}';
  String _consumerId(String value) => 'consumer_${_id(value)}';
  String _supportingTypeId(String value) => 'supporting_type_${_id(value)}';
  String _contractComponentId(String value) =>
      'contract_component_${_id(value)}';
  String _implementationComponentId(String value) {
    return 'implementation_component_${_id(value)}';
  }

  String _contractId(ComponentContract contract) {
    return 'contract_${_id(contract.identity)}';
  }

  String _contractIdByIdentity(String value) => 'contract_${_id(value)}';

  String _implementationId(ImplementedContract contract) {
    return 'implementation_${_id('${contract.implementationComponent}_${contract.implementationClass}')}';
  }

  String _id(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _escape(String value) => value.replaceAll('"', r'\"');

  bool _isSupportingDomainType(ComponentContract contract) {
    return contract.isSupportingDomainType;
  }

  List<ComponentContract> _behaviorContractsFor(String componentName) {
    return graph.contracts
        .where(
          (contract) =>
              contract.ownerComponent == componentName &&
              contract.isBehaviorContract,
        )
        .toList();
  }

  List<ComponentContract> _behaviorContracts() {
    return graph.contracts
        .where((contract) => contract.isBehaviorContract)
        .toList();
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

  Set<String> _supportingTypesFor(List<ComponentContract> contracts) {
    return {
      for (final contract in contracts)
        for (final method in contract.methods) ...[
          ...method.requestTypes.where((type) => type != 'None'),
          ...method.responseTypes.where((type) => type != 'None'),
        ],
    };
  }

  String _contractListLabel(String action, Set<String> contracts) {
    final sorted = contracts.toList()..sort();
    if (sorted.length == 1) return '$action ${sorted.single}';
    return '$action ${sorted.length} contracts';
  }

  String _hldUsesLabel(Set<String> uses, Set<String>? implementsContracts) {
    if (implementsContracts != null &&
        uses.intersection(implementsContracts).isNotEmpty) {
      return 'depends on API';
    }
    return _contractListLabel('uses', uses);
  }

  int _compareContracts(ComponentContract a, ComponentContract b) {
    final owner = a.ownerComponent.compareTo(b.ownerComponent);
    if (owner != 0) return owner;
    return a.name.compareTo(b.name);
  }

  int _compareImplementedContracts(
    ImplementedContract a,
    ImplementedContract b,
  ) {
    final contract = a.contractName.compareTo(b.contractName);
    if (contract != 0) return contract;
    final component = a.implementationComponent.compareTo(
      b.implementationComponent,
    );
    if (component != 0) return component;
    return a.implementationClass.compareTo(b.implementationClass);
  }

  int _compareConsumedContracts(ConsumedContract a, ConsumedContract b) {
    final contract = a.contractName.compareTo(b.contractName);
    if (contract != 0) return contract;
    final consumer = a.consumerComponent.compareTo(b.consumerComponent);
    if (consumer != 0) return consumer;
    return a.providerComponent.compareTo(b.providerComponent);
  }

  int _compareNodes(_Node a, _Node b) {
    final label = a.label.compareTo(b.label);
    if (label != 0) return label;
    return a.id.compareTo(b.id);
  }

  int _compareEdges(_Edge a, _Edge b) {
    final from = a.from.compareTo(b.from);
    if (from != 0) return from;
    final to = a.to.compareTo(b.to);
    if (to != 0) return to;
    return a.label.compareTo(b.label);
  }

  int _compareDiagramEdges(DiagramEdge a, DiagramEdge b) {
    final from = a.from.compareTo(b.from);
    if (from != 0) return from;
    final to = a.to.compareTo(b.to);
    if (to != 0) return to;
    return a.label.compareTo(b.label);
  }
}

class _Node {
  final String id;
  final String label;

  _Node(this.id, this.label);
}

class _Edge {
  final String from;
  final String to;
  final String label;

  _Edge(this.from, this.to, this.label);
}
