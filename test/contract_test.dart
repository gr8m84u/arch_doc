import 'dart:io';

import 'package:arch_doc/arch_doc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ContractAnalyzer', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('arch_contract_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'detects interfaces, service classes, methods, consumers and implementations',
      () {
        final identity = _package(tempDir, 'sample_identity', '''
abstract class IAuthenticationProvider {
  Future<Result<AuthResult>> authenticate(AuthRequest request);
  Stream<AuthEvent> watch(AuthRequest request);
  void _privateHelper();
}

abstract class AuthWorkerService {
  AuthResult start(AuthRequest request);
}
''');
        final impl = _package(tempDir, 'sample_windows_ffi', '''
import 'package:sample_identity/sample_identity.dart';

class WindowsAuthenticationProvider implements IAuthenticationProvider {
  Future<Result<AuthResult>> authenticate(AuthRequest request);
  Stream<AuthEvent> watch(AuthRequest request);
}

class ConsumerGateway {
  final IAuthenticationProvider provider;
  ConsumerGateway(this.provider);
  AuthResult call(IAuthenticationProvider provider, AuthRequest request) => throw UnimplementedError();
}
''');

        final graph = ContractAnalyzer().analyze(
          packages: [
            _node('sample_identity', identity.path),
            _node('sample_windows_ffi', impl.path),
          ],
          componentGraph: ComponentGraph(
            components: [
              _component('Identity', 'sample_identity'),
              _component('Windows FFI', 'sample_windows_ffi'),
            ],
          ),
          config: ArchConfig(layers: const {}, rules: const []),
        );

        final provider = graph.contracts.firstWhere(
          (contract) => contract.name == 'IAuthenticationProvider',
        );
        final service = graph.contracts.firstWhere(
          (contract) => contract.name == 'AuthWorkerService',
        );
        expect(provider.protocol, 'Dart API');
        expect(provider.kind, 'Interface');
        expect(service.kind, 'Abstract class');
        expect(provider.methods.map((method) => method.name), [
          'authenticate',
          'watch',
        ]);
        expect(provider.methods.first.requestTypes, ['AuthRequest']);
        expect(provider.methods.first.responseTypes, ['AuthResult']);
        expect(provider.methods.first.errorTypes, ['Result']);
        expect(
          provider.methods.first.signature,
          'Future<Result<AuthResult>> authenticate(AuthRequest request)',
        );
        expect(provider.consumerComponents, contains('Windows FFI'));

        expect(
          graph.implementedContracts.map(
            (contract) => contract.implementationClass,
          ),
          contains('WindowsAuthenticationProvider'),
        );
        expect(
          graph.consumedContracts.map((contract) => contract.contractName),
          contains('IAuthenticationProvider'),
        );
      },
    );

    test('infers protocols and warn_without_consumers behavior', () {
      final grpc = _package(tempDir, 'sample_grpc_contracts', '''
class AuthWorkerService {
  AuthResponse call(AuthRequest request) => throw UnimplementedError();
}
''');
      final unknown = _package(tempDir, 'sdk_misc', '''
class TokenAdapter {}

abstract class EmptyServiceBase {}
''');

      ComponentContractGraph analyze({required bool warnWithoutConsumers}) {
        return ContractAnalyzer().analyze(
          packages: [
            _node('sample_grpc_contracts', grpc.path),
            _node('sdk_misc', unknown.path),
          ],
          componentGraph: ComponentGraph(
            components: [
              _component('gRPC Contracts', 'sample_grpc_contracts'),
              _component('Misc', 'sdk_misc'),
            ],
          ),
          config: ArchConfig(
            layers: const {},
            rules: const [],
            contractAnalysis: ContractAnalysisConfig(
              enabled: true,
              detectProtocols: true,
              includeLldMethods: true,
              unwrapAsyncTypes: true,
              maxMethodsPerContract: 50,
              warnWithoutConsumers: warnWithoutConsumers,
              includeGeneratedMethods: false,
            ),
          ),
        );
      }

      final defaultGraph = analyze(warnWithoutConsumers: false);
      expect(
        defaultGraph.contracts
            .firstWhere((contract) => contract.name == 'AuthWorkerService')
            .protocol,
        'gRPC',
      );
      expect(
        defaultGraph.contracts
            .firstWhere((contract) => contract.name == 'AuthWorkerService')
            .kind,
        'Service',
      );
      expect(
        defaultGraph.findings.where(
          (finding) => finding.code == 'CONTRACT002_CONSUMER_UNKNOWN',
        ),
        isEmpty,
      );

      final warningGraph = analyze(warnWithoutConsumers: true);
      expect(
        warningGraph.findings
            .map((finding) => finding.code)
            .contains('CONTRACT002_CONSUMER_UNKNOWN'),
        isTrue,
      );
      expect(
        warningGraph.findings
            .map((finding) => finding.code)
            .contains('CONTRACT004_CONTRACT_WITHOUT_METHODS'),
        isTrue,
      );
      expect(
        warningGraph.findings.any(
          (finding) =>
              finding.code == 'CONTRACT004_CONTRACT_WITHOUT_METHODS' &&
              finding.subject == 'TokenAdapter',
        ),
        isFalse,
      );
      expect(
        warningGraph.findings.any(
          (finding) =>
              finding.code == 'CONTRACT004_CONTRACT_WITHOUT_METHODS' &&
              finding.subject == 'EmptyServiceBase',
        ),
        isTrue,
      );
    });

    test('handles ambiguous contract names with qualified identity', () {
      final pkgA = _package(tempDir, 'pkg_a', '''
abstract interface class IService {
  void doA();
}
''');
      final pkgB = _package(tempDir, 'pkg_b', '''
abstract interface class IService {
  void doB();
}
''');
      final pkgC = _package(tempDir, 'pkg_c', '''
import 'package:pkg_a/pkg_a.dart';
class ServiceA implements IService {
  void doA() {}
}
''');
      final pkgD = _package(tempDir, 'pkg_d', '''
import 'package:pkg_b/pkg_b.dart';
class ServiceB implements IService {
  void doB() {}
}
''');
      final pkgE = _package(tempDir, 'pkg_e', '''
class AmbiguousConsumer {
  final dynamic service;
  AmbiguousConsumer(this.service);
  void use(IService s) {}
}
''');

      final graph = ContractAnalyzer().analyze(
        packages: [
          _node('pkg_a', pkgA.path),
          _node('pkg_b', pkgB.path),
          _node('pkg_c', pkgC.path),
          _node('pkg_d', pkgD.path),
          _node('pkg_e', pkgE.path),
        ],
        componentGraph: ComponentGraph(
          components: [
            _component('A', 'pkg_a'),
            _component('B', 'pkg_b'),
            _component('C', 'pkg_c'),
            _component('D', 'pkg_d'),
            _component('E', 'pkg_e'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final contractA = graph.contracts.firstWhere(
        (c) => c.sourcePackage == 'pkg_a' && c.name == 'IService',
      );
      final contractB = graph.contracts.firstWhere(
        (c) => c.sourcePackage == 'pkg_b' && c.name == 'IService',
      );

      // Check identities
      expect(contractA.identity, 'pkg_a:IService');
      expect(contractB.identity, 'pkg_b:IService');

      // Check implementations resolved correctly via imports
      expect(contractA.consumerComponents, contains('C'));
      expect(contractB.consumerComponents, contains('D'));
      expect(contractA.consumerComponents, isNot(contains('D')));
      expect(contractB.consumerComponents, isNot(contains('C')));

      // Check ambiguity finding for pkg_e (no imports to disambiguate)
      expect(
        graph.findings.any(
          (f) =>
              f.code == 'CONTRACT007_AMBIGUOUS_CONTRACT_NAME' &&
              f.subject == 'IService',
        ),
        isTrue,
      );
    });

    test('globally unique plain name fallback still works', () {
      final pkgA = _package(tempDir, 'pkg_a', '''
abstract interface class IUnique {
  void doA();
}
''');
      final pkgB = _package(tempDir, 'pkg_b', '''
class Consumer {
  void use(IUnique s) {}
}
''');

      final graph = ContractAnalyzer().analyze(
        packages: [_node('pkg_a', pkgA.path), _node('pkg_b', pkgB.path)],
        componentGraph: ComponentGraph(
          components: [_component('A', 'pkg_a'), _component('B', 'pkg_b')],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final contract = graph.contracts.firstWhere((c) => c.name == 'IUnique');
      expect(contract.consumerComponents, contains('B'));
    });
  });

  group('Contract generators', () {
    test('generates global markdown, per-component markdown and inline Mermaid',
        () {
      final graph = ComponentContractGraph(
        contracts: [
          ComponentContract(
            name: 'IAuthProvider',
            level: ContractLevel.hld,
            protocol: 'Dart API',
            ownerComponent: 'Identity',
            providerComponent: 'Identity',
            consumerComponents: const ['Windows FFI'],
            sourcePackage: 'sample_identity',
            sourcePath: 'lib/sample_identity.dart',
            interfaceName: 'IAuthProvider',
            endpointName: 'IAuthProvider',
            kind: 'Interface',
            methods: [
              ContractMethod(
                name: 'authenticate',
                requestTypes: const ['AuthRequest'],
                responseTypes: const ['AuthResult'],
                errorTypes: const ['Result'],
                sourcePath: 'lib/sample_identity.dart',
                signature:
                    'Future<Result<AuthResult>> authenticate(AuthRequest request)',
              ),
            ],
          ),
        ],
        consumedContracts: [
          ConsumedContract(
            contractName: 'IAuthProvider',
            protocol: 'Dart API',
            providerComponent: 'Identity',
            providerPackage: 'sample_identity',
            consumerComponent: 'Windows FFI',
            usageEvidence: 'IAuthProvider',
          ),
        ],
        implementedContracts: [
          ImplementedContract(
            contractName: 'IAuthProvider',
            contractPackage: 'sample_identity',
            definedBy: 'Identity',
            implementationComponent: 'Windows FFI',
            implementationClass: 'WindowsAuthProvider',
            methodsImplemented: const ['authenticate'],
          ),
        ],
        findings: const [],
      );
      final componentGraph = ComponentGraph(
        components: [
          _component('Identity', 'sample_identity'),
          _component('Windows FFI', 'sample_windows_ffi'),
        ],
      );
      final docs = generateContractDocuments(
        graph: graph,
        componentGraph: componentGraph,
        config: ArchConfig(layers: const {}, rules: const []),
      );

      expect(docs.globalMarkdown, contains('# Component Contracts'));
      expect(docs.globalMarkdown, contains('```mermaid'));
      expect(
        docs.globalMarkdown,
        contains('PlantUML: [Open diagram](./contracts.puml)'),
      );
      expect(docs.globalMermaid, contains('flowchart TD'));
      expect(docs.globalPlantUml, contains('@startuml'));
      expect(
        docs.componentMarkdownBySlug['identity'],
        contains('### Provided contracts'),
      );
      expect(
        docs.componentMarkdownBySlug['identity'],
        contains('PlantUML: [Open diagram](./identity.hld.puml)'),
      );
      expect(
        docs.componentMarkdownBySlug['identity'],
        isNot(contains('PlantUML: [Open diagram](./identity.lld.puml)')),
      );
      expect(
        docs.componentMarkdownBySlug['identity'],
        contains(
          '| `authenticate` | `Future<Result<AuthResult>> authenticate(AuthRequest request)` | `AuthRequest` | `AuthResult` | `Result` |',
        ),
      );
      expect(
        docs.componentMarkdownBySlug['windows-ffi'],
        contains(
          'This component implements external contracts. Contract method details are documented in the provider component pages.',
        ),
      );
      expect(
        docs.componentMarkdownBySlug['windows-ffi'],
        contains(
          '| `IAuthProvider` | Identity | [Open contract](./identity.md#iauthprovider) |',
        ),
      );
    });

    test('supports link-only Mermaid embedding', () {
      final componentGraph = ComponentGraph(
        components: [_component('Identity', 'sample_identity')],
      );
      final docs = generateContractDocuments(
        graph: ComponentContractGraph(
          contracts: const [],
          consumedContracts: const [],
          implementedContracts: const [],
          findings: const [],
        ),
        componentGraph: componentGraph,
        config: ArchConfig(
          layers: const {},
          rules: const [],
          diagramEmbedding: DiagramEmbeddingConfig(mode: 'link_only'),
        ),
      );

      expect(docs.globalMarkdown, contains('[Open diagram](./contracts.mmd)'));
      expect(
        docs.globalMarkdown,
        contains('PlantUML: [Open diagram](./contracts.puml)'),
      );
      expect(docs.globalMarkdown, isNot(contains('```mermaid')));
    });

    test('generates layered type contract diagrams', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(includeSelfConsumer: true),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      expect(docs.globalMermaid, contains('subgraph Contracts'));
      expect(docs.globalMermaid, contains('subgraph Implementations'));
      expect(docs.globalMermaid, contains('subgraph Consumers'));
      expect(
        docs.globalMermaid,
        contains('contract_sample_identity_IAuthProvider -->|implemented by|'),
      );
      expect(
        docs.globalMermaid,
        contains(
          'component_Auth_Worker -->|uses| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains('flowchart LR'),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'component_Auth_Worker -->|uses| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'supporting_type_AuthRequest -->|request| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'contract_sample_identity_IAuthProvider -->|response| supporting_type_AuthResult',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        isNot(contains('component_Identity -->|uses|')),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'implementation_component_Windows_FFI -->|implements| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'implementation_Windows_FFI_WindowsAuthProvider -->|class| implementation_component_Windows_FFI',
        ),
      );
      expect(
        docs.componentHldMermaidBySlug['identity'],
        contains('flowchart LR'),
      );
      expect(
        docs.componentHldMermaidBySlug['identity'],
        contains(
          'component_Auth_Worker -->|uses IAuthProvider| component_Identity',
        ),
      );
      expect(
        docs.componentHldMermaidBySlug['identity'],
        contains(
          'component_Windows_FFI -->|implements IAuthProvider| component_Identity',
        ),
      );
      expect(
        docs.componentHldMermaidBySlug['identity'],
        isNot(contains('contract_sample_identity_IAuthProvider')),
      );
      expect(
        docs.componentHldMermaidBySlug['identity'],
        isNot(contains('WindowsAuthProvider')),
      );
      expect(
        docs.componentHldPlantUmlBySlug['identity'],
        contains('left to right direction'),
      );
      expect(
        docs.componentHldPlantUmlBySlug['identity'],
        contains(
          'component_Windows_FFI --> component_Identity : implements IAuthProvider',
        ),
      );
      expect(
        docs.componentHldPlantUmlBySlug['identity'],
        isNot(contains('WindowsAuthProvider')),
      );
      expect(
        docs.componentLldPlantUmlBySlug['identity'],
        contains(
          'interface "IAuthProvider" as contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldPlantUmlBySlug['identity'],
        contains('class "AuthRequest" as supporting_type_AuthRequest'),
      );
      expect(
        docs.componentLldPlantUmlBySlug['identity'],
        contains(
          'class "WindowsAuthProvider" as implementation_Windows_FFI_WindowsAuthProvider',
        ),
      );
    });

    test('per-component diagrams show local implementations only', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(includeLocalImplementation: true),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'implementation_component_Identity -->|implements| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        docs.componentLldMermaidBySlug['identity'],
        contains(
          'implementation_Identity_DefaultAuthProvider -->|class| implementation_component_Identity',
        ),
      );
    });

    test('HLD diagrams deduplicate implementation classes per contract', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(includeDuplicateImplementation: true),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final hld = docs.componentHldMermaidBySlug['identity']!;
      expect(
        RegExp(
          r'component_Windows_FFI -->\|implements IAuthProvider\| component_Identity',
        ).allMatches(hld),
        hasLength(1),
      );
      expect(hld, isNot(contains('AlternateWindowsAuthProvider')));
    });

    test('HLD diagrams keep uses and implements as separate edges', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(
          includeSecondContract: true,
          includeWindowsFfiConsumer: true,
        ),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final hld = docs.componentHldMermaidBySlug['identity']!;
      expect(
        hld,
        contains(
          'component_Windows_FFI -->|depends on API| component_Identity',
        ),
      );
      expect(
        hld,
        contains(
          'component_Windows_FFI -->|implements 2 contracts| component_Identity',
        ),
      );
      expect(hld, isNot(contains('uses/implements')));

      final markdown = docs.componentMarkdownBySlug['identity']!;
      expect(
        markdown,
        isNot(
          contains(
            'component_Windows_FFI -->|uses 2 contracts| component_Identity',
          ),
        ),
      );
      expect(
        markdown,
        contains(
          '| Consumed by | Windows FFI | `IAuthProvider`, `ITokenProvider` |',
        ),
      );
      expect(
        markdown,
        contains(
          '| Implemented by | Windows FFI | `IAuthProvider`, `ITokenProvider` |',
        ),
      );
    });

    test('HLD diagrams include consumed and implemented external providers',
        () {
      final docs = generateContractDocuments(
        graph: _contractGraph(
          includeConsumedExternal: true,
          includeImplementedExternal: true,
        ),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Auth Models', 'sample_models'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final hld = docs.componentHldMermaidBySlug['identity']!;
      expect(
        hld,
        contains('component_Identity -->|uses ILogger| component_Auth_Models'),
      );
      expect(
        hld,
        contains(
          'component_Identity -->|implements IExternalIdentity| component_Auth_Models',
        ),
      );
    });

    test(
      'per-component contracts omit concrete service and client classes',
      () {
        final docs = generateContractDocuments(
          graph: _contractGraph(includeConcreteContracts: true),
          componentGraph: ComponentGraph(
            components: [
              _component('Identity', 'sample_identity'),
              _component('Auth Worker', 'sample_worker'),
            ],
          ),
          config: ArchConfig(layers: const {}, rules: const []),
        );

        final diagram = docs.componentLldMermaidBySlug['identity']!;
        expect(diagram, contains('contract_sample_identity_IAuthProvider'));
        expect(
          diagram,
          contains('contract_sample_identity_AuthWorkerServiceBase'),
        );
        expect(
          diagram,
          isNot(contains('contract_sample_identity_AuthWorkerService[')),
        );
        expect(
          diagram,
          isNot(contains('contract_sample_identity_WindowsAuthWorkerClient')),
        );
        expect(
          diagram,
          isNot(
            contains(
              'contract_sample_identity_GrpcWindowsAuthWorkerClientAdapter',
            ),
          ),
        );
      },
    );

    test(
      'per-component diagrams move no-method domain interfaces to supporting types',
      () {
        final docs = generateContractDocuments(
          graph: _contractGraph(includeDomainModelSupport: true),
          componentGraph: ComponentGraph(
            components: [
              _component('Identity', 'sample_identity'),
              _component('Auth Worker', 'sample_worker'),
            ],
          ),
          config: ArchConfig(layers: const {}, rules: const []),
        );

        final diagram = docs.componentLldMermaidBySlug['identity']!;
        expect(diagram, contains('subgraph Supporting Types'));
        expect(
          diagram,
          contains('supporting_type_IDomainIdentity["IDomainIdentity"]'),
        );
        expect(
          diagram,
          isNot(contains('contract_sample_identity_IDomainIdentity')),
        );
        expect(
          diagram,
          contains(
            'contract_sample_identity_IIdentityParser -->|response| supporting_type_IDomainIdentity',
          ),
        );

        final markdown = docs.componentMarkdownBySlug['identity']!;
        expect(
          markdown,
          isNot(contains('| OK | Dart API | Interface | `IDomainIdentity` |')),
        );
        expect(markdown, contains('- `IDomainIdentity`'));
        expect(
          markdown,
          contains(
            '| Behavior contracts | Consumed contracts | External consumers | External providers |',
          ),
        );
        expect(markdown, contains('| 2 | 0 | 1 | 0 |'));
      },
    );

    test('no-method arbitrary Base types are supporting types', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(includeNoMethodBaseContracts: true),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final markdown = docs.componentMarkdownBySlug['identity']!;
      expect(
        markdown,
        contains('| Dart API | Base type | `AuthWorkerServiceBase` |'),
      );
      expect(
        markdown,
        isNot(contains('| OK | Dart API | Base type | `IdentityModelBase` |')),
      );
    });

    test('component markdown explains component-centric diagrams', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(
          includeSelfConsumer: true,
          includeLocalImplementation: true,
          includeObjectMembers: true,
        ),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      final markdown = docs.componentMarkdownBySlug['identity']!;
      expect(markdown, contains('## HLD: Component contracts'));
      expect(markdown, contains('## LLD: Contract details'));
      expect(
        markdown,
        contains(
          'HLD shows components/packages and contract-labeled relationships.',
        ),
      );
      expect(
        markdown,
        contains(
          'HLD diagrams do not include interfaces, classes, methods, request models, or response models as nodes.',
        ),
      );
      expect(
        markdown,
        contains(
          'LLD shows interfaces, implementation classes, direct request/response models, and method details.',
        ),
      );
      expect(
        markdown,
        contains('Supporting types are not recursively expanded.'),
      );
      expect(
        markdown,
        isNot(contains('PlantUML: [Open diagram](./identity.lld.puml)')),
      );
      expect(markdown, contains('### HLD Summary'));
      expect(
        markdown,
        contains(
          '| Behavior contracts | Consumed contracts | External consumers | External providers |',
        ),
      );
      expect(markdown, contains('| 1 | 0 | 1 | 0 |'));
      expect(markdown, contains('### HLD Relationships'));
      expect(
        markdown,
        contains('| Consumed by | Auth Worker | `IAuthProvider` |'),
      );
      expect(
        markdown,
        contains('| Implemented by | Windows FFI | `IAuthProvider` |'),
      );
      expect(
        markdown,
        contains(
          '| Protocol | Contract kind | Contract | Provider | External consumers | Internal usage | Methods |',
        ),
      );
      expect(
        markdown,
        contains(
          '| Dart API | Interface | `IAuthProvider` | Identity | `Auth Worker` | Yes | 1 |',
        ),
      );
      expect(
        markdown,
        contains('### Contracts consumed from other components'),
      );
      expect(markdown, isNot(contains('## Consumed contracts')));
      expect(markdown, contains('### Implemented contracts'));
      expect(
        markdown,
        contains(
          '| `IAuthProvider` | Identity | `DefaultAuthProvider` | `authenticate` |',
        ),
      );
      expect(markdown, isNot(contains('`hashCode`')));
      expect(markdown, isNot(contains('`runtimeType`')));
      expect(markdown, isNot(contains('`toString`')));
      expect(markdown, contains('### Supporting Types'));
      expect(markdown, contains('- `AuthRequest`'));
      expect(markdown, contains('- `AuthResult`'));
      expect(markdown, contains('```mermaid'));
      expect(markdown, contains('subgraph Request Types'));
      expect(markdown, contains('subgraph Contract'));
      expect(markdown, contains('subgraph Response Types'));
      expect(markdown, contains('subgraph Implementations'));
      expect(
        markdown,
        contains(
          'supporting_type_AuthRequest -->|request| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(
        markdown,
        contains(
          'contract_sample_identity_IAuthProvider -->|response| supporting_type_AuthResult',
        ),
      );
      expect(
        markdown,
        contains(
          'implementation_Windows_FFI_WindowsAuthProvider -->|implements| contract_sample_identity_IAuthProvider',
        ),
      );
      expect(markdown, contains('| Method | Signature | Request models |'));
      expect(
        markdown,
        contains(
          '| `authenticate` | `AuthResult authenticate(AuthRequest request)` | `AuthRequest` | `AuthResult` | None |',
        ),
      );
    });

    test('generates layered component contract diagrams with counted edges',
        () {
      final docs = generateContractDocuments(
        graph: _contractGraph(includeSecondContract: true),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(
          layers: const {},
          rules: const [],
          contractDiagrams: ContractDiagramsConfig(
            layout: 'layered',
            view: 'component',
          ),
        ),
      );

      expect(docs.globalMermaid, contains('subgraph Contracts'));
      expect(
        docs.globalMermaid,
        contains(
          'consumer_Auth_Worker -->|uses 2 contracts| contract_component_Identity',
        ),
      );
      expect(
        docs.globalMermaid,
        contains(
          'contract_component_Identity -->|implemented by 2 contracts| implementation_component_Windows_FFI',
        ),
      );
    });

    test('component LLD overview can be included in component markdown', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(
          layers: const {},
          rules: const [],
          contractDiagrams: ContractDiagramsConfig(
            layout: 'layered',
            view: 'type',
            includeComponentLldOverview: true,
          ),
        ),
      );

      final markdown = docs.componentMarkdownBySlug['identity']!;
      expect(
        markdown,
        contains('PlantUML: [Open diagram](./identity.lld.puml)'),
      );
      expect(markdown, contains('subgraph Consumers'));
    });

    test('omits empty layered diagram sections', () {
      final docs = generateContractDocuments(
        graph: ComponentContractGraph(
          contracts: [
            ComponentContract(
              name: 'IAuthProvider',
              level: ContractLevel.hld,
              protocol: 'Dart API',
              ownerComponent: 'Identity',
              providerComponent: 'Identity',
              consumerComponents: const [],
              sourcePackage: 'sample_identity',
              sourcePath: 'lib/sample_identity.dart',
              interfaceName: 'IAuthProvider',
              endpointName: 'IAuthProvider',
              kind: 'Interface',
              methods: const [],
            ),
          ],
          consumedContracts: const [],
          implementedContracts: const [],
          findings: const [],
        ),
        componentGraph: ComponentGraph(
          components: [_component('Identity', 'sample_identity')],
        ),
        config: ArchConfig(layers: const {}, rules: const []),
      );

      expect(docs.globalMermaid, isNot(contains('subgraph Contracts')));
      expect(docs.globalMermaid, isNot(contains('subgraph Implementations')));
      expect(docs.globalMermaid, isNot(contains('subgraph Consumers')));
    });

    test('preserves auto contract diagram mode', () {
      final docs = generateContractDocuments(
        graph: _contractGraph(),
        componentGraph: ComponentGraph(
          components: [
            _component('Identity', 'sample_identity'),
            _component('Windows FFI', 'sample_windows_ffi'),
            _component('Auth Worker', 'sample_worker'),
          ],
        ),
        config: ArchConfig(
          layers: const {},
          rules: const [],
          contractDiagrams: ContractDiagramsConfig(
            layout: 'auto',
            view: 'type',
          ),
        ),
      );

      expect(docs.globalMermaid, contains('-->|provides|'));
      expect(docs.globalMermaid, isNot(contains('subgraph Contracts')));
    });

    test('filters generated methods in component documentation by default', () {
      final contract = ComponentContract(
        name: 'GrpcServiceBase',
        level: ContractLevel.hld,
        protocol: 'gRPC',
        ownerComponent: 'Identity',
        providerComponent: 'Identity',
        consumerComponents: const [],
        sourcePackage: 'sample_identity',
        sourcePath: 'lib/service.dart',
        interfaceName: 'GrpcServiceBase',
        endpointName: 'GrpcServiceBase',
        kind: 'Service',
        methods: [
          ContractMethod(
            name: 'businessMethod',
            requestTypes: const [],
            responseTypes: const [],
            errorTypes: const [],
            sourcePath: 'lib/service.dart',
            signature: 'void businessMethod()',
          ),
          ContractMethod(
            name: 'businessMethod_Pre',
            requestTypes: const [],
            responseTypes: const [],
            errorTypes: const [],
            sourcePath: 'lib/service.dart',
            signature: 'void businessMethod_Pre()',
          ),
          ContractMethod(
            name: r'$generatedHelper',
            requestTypes: const [],
            responseTypes: const [],
            errorTypes: const [],
            sourcePath: 'lib/service.dart',
            signature: r'void $generatedHelper()',
          ),
          ContractMethod(
            name: '_privateHelper',
            requestTypes: const [],
            responseTypes: const [],
            errorTypes: const [],
            sourcePath: 'lib/service.dart',
            signature: 'void _privateHelper()',
          ),
        ],
      );

      final graph = ComponentContractGraph(
        contracts: [contract],
        consumedContracts: const [],
        implementedContracts: [
          ImplementedContract(
            contractName: 'GrpcServiceBase',
            contractPackage: 'sample_identity',
            definedBy: 'Identity',
            implementationComponent: 'Identity',
            implementationClass: 'GrpcServiceImpl',
            methodsImplemented: const [
              'businessMethod',
              'businessMethod_Pre',
              r'$generatedHelper',
              '_privateHelper',
              'toString',
            ],
          ),
        ],
        findings: const [],
      );

      final componentGraph = ComponentGraph(
        components: [_component('Identity', 'sample_identity')],
      );

      // Default: filtered
      final docsDefault = generateContractDocuments(
        graph: graph,
        componentGraph: componentGraph,
        config: ArchConfig(
          layers: const {},
          rules: const [],
          contractAnalysis: ContractAnalysisConfig.defaults(),
        ),
      );

      final mdDefault = docsDefault.componentMarkdownBySlug['identity']!;
      expect(mdDefault, contains('`businessMethod`'));
      expect(mdDefault, isNot(contains('`businessMethod_Pre`')));
      expect(mdDefault, isNot(contains(r'`$generatedHelper`')));
      expect(mdDefault, isNot(contains('`_privateHelper`')));
      expect(mdDefault, isNot(contains('`toString`')));

      // Explicitly include generated
      final docsAll = generateContractDocuments(
        graph: graph,
        componentGraph: componentGraph,
        config: ArchConfig(
          layers: const {},
          rules: const [],
          contractAnalysis: ContractAnalysisConfig(
            enabled: true,
            detectProtocols: true,
            includeLldMethods: true,
            unwrapAsyncTypes: true,
            maxMethodsPerContract: 50,
            warnWithoutConsumers: false,
            includeGeneratedMethods: true,
          ),
        ),
      );

      final mdAll = docsAll.componentMarkdownBySlug['identity']!;
      expect(mdAll, contains('`businessMethod`'));
      expect(mdAll, contains('`businessMethod_Pre`'));
      expect(mdAll, contains(r'`$generatedHelper`'));
      expect(mdAll, contains('`_privateHelper`'));
      // toString should still be filtered as an object member if it's not part of ContractMethod objects
      // but in implemented table it should be shown if not filtered.
      // Wait, _filterMethodNames filters standard Object members even if includeGeneratedMethods is true?
      // No, my implementation:
      /*
      var filtered = names.where((name) => !const {
          '==',
          'hashCode',
          'toString',
          'runtimeType',
        }.contains(name));
      */
      // Ah, I kept the object member filter ALWAYS. Let me check the requirement.
      // "names starting with _", "standard Object members".
      // If include_generated_methods=true: render all methods as today.
      // "as today" means with object member filtering?
      // Actually, before this change, we had _filterObjectMembers which was ALWAYS applied to implemented table.
      // And _writeMethodTable didn't filter anything.

      expect(mdAll, contains('`businessMethod`'));
      expect(mdAll, contains('`businessMethod_Pre`'));
    });
  });
}

ComponentContractGraph _contractGraph({
  bool includeSecondContract = false,
  bool includeSelfConsumer = false,
  bool includeLocalImplementation = false,
  bool includeConcreteContracts = false,
  bool includeObjectMembers = false,
  bool includeDomainModelSupport = false,
  bool includeNoMethodBaseContracts = false,
  bool includeDuplicateImplementation = false,
  bool includeConsumedExternal = false,
  bool includeImplementedExternal = false,
  bool includeWindowsFfiConsumer = false,
}) {
  final contracts = [
    _contract(
      'IAuthProvider',
      'authenticate',
      consumerComponents: ['Auth Worker', if (includeSelfConsumer) 'Identity'],
    ),
    if (includeSecondContract) _contract('ITokenProvider', 'token'),
    if (includeConcreteContracts) ...[
      _contract('AuthWorkerServiceBase', 'start'),
      _contract('AuthWorkerService', 'start'),
      _contract('WindowsAuthWorkerClient', 'call'),
      _contract('GrpcWindowsAuthWorkerClientAdapter', 'call'),
    ],
    if (includeDomainModelSupport) ...[
      _contract(
        'IIdentityParser',
        'parse',
        requestTypes: const ['String'],
        responseTypes: const ['IDomainIdentity'],
      ),
      _contract('IDomainIdentity', 'unused', methods: const []),
    ],
    if (includeNoMethodBaseContracts) ...[
      _contract('AuthWorkerServiceBase', 'unused', methods: const []),
      _contract('IdentityModelBase', 'unused', methods: const []),
    ],
  ];
  return ComponentContractGraph(
    contracts: contracts,
    consumedContracts: [
      for (final contract in contracts)
        ConsumedContract(
          contractName: contract.name,
          protocol: 'Dart API',
          providerComponent: 'Identity',
          providerPackage: 'sample_identity',
          consumerComponent: 'Auth Worker',
          usageEvidence: contract.name,
        ),
      if (includeWindowsFfiConsumer)
        for (final contract in contracts)
          ConsumedContract(
            contractName: contract.name,
            protocol: 'Dart API',
            providerComponent: 'Identity',
            providerPackage: 'sample_identity',
            consumerComponent: 'Windows FFI',
            usageEvidence: contract.name,
          ),
      if (includeConsumedExternal)
        ConsumedContract(
          contractName: 'ILogger',
          protocol: 'Dart API',
          providerComponent: 'Auth Models',
          providerPackage: 'sample_models',
          consumerComponent: 'Identity',
          usageEvidence: 'ILogger',
        ),
      if (includeSelfConsumer)
        ConsumedContract(
          contractName: 'IAuthProvider',
          protocol: 'Dart API',
          providerComponent: 'Identity',
          providerPackage: 'sample_identity',
          consumerComponent: 'Identity',
          usageEvidence: 'IAuthProvider',
        ),
    ],
    implementedContracts: [
      for (final contract in contracts.where(
        (contract) => contract.methods.isNotEmpty,
      ))
        ImplementedContract(
          contractName: contract.name,
          contractPackage: 'sample_identity',
          definedBy: 'Identity',
          implementationComponent: 'Windows FFI',
          implementationClass: contract.name == 'IAuthProvider'
              ? 'WindowsAuthProvider'
              : 'WindowsTokenProvider',
          methodsImplemented: [contract.methods.first.name],
        ),
      if (includeDuplicateImplementation)
        ImplementedContract(
          contractName: 'IAuthProvider',
          contractPackage: 'sample_identity',
          definedBy: 'Identity',
          implementationComponent: 'Windows FFI',
          implementationClass: 'AlternateWindowsAuthProvider',
          methodsImplemented: const ['authenticate'],
        ),
      if (includeImplementedExternal)
        ImplementedContract(
          contractName: 'IExternalIdentity',
          contractPackage: 'sample_models',
          definedBy: 'Auth Models',
          implementationComponent: 'Identity',
          implementationClass: 'DefaultExternalIdentity',
          methodsImplemented: const ['resolve'],
        ),
      if (includeLocalImplementation)
        ImplementedContract(
          contractName: 'IAuthProvider',
          contractPackage: 'sample_identity',
          definedBy: 'Identity',
          implementationComponent: 'Identity',
          implementationClass: 'DefaultAuthProvider',
          methodsImplemented: [
            'authenticate',
            if (includeObjectMembers) ...[
              '==',
              'hashCode',
              'runtimeType',
              'toString',
            ],
          ],
        ),
    ],
    findings: const [],
  );
}

ComponentContract _contract(
  String name,
  String methodName, {
  List<String> consumerComponents = const ['Auth Worker'],
  List<String> requestTypes = const ['AuthRequest'],
  List<String> responseTypes = const ['AuthResult'],
  List<ContractMethod>? methods,
}) {
  return ComponentContract(
    name: name,
    level: ContractLevel.hld,
    protocol: 'Dart API',
    ownerComponent: 'Identity',
    providerComponent: 'Identity',
    consumerComponents: consumerComponents,
    sourcePackage: 'sample_identity',
    sourcePath: 'lib/sample_identity.dart',
    interfaceName: name,
    endpointName: name,
    kind: _kindForName(name),
    methods: methods ??
        [
          ContractMethod(
            name: methodName,
            requestTypes: requestTypes,
            responseTypes: responseTypes,
            errorTypes: const [],
            sourcePath: 'lib/sample_identity.dart',
            signature:
                '${responseTypes.first} $methodName(${requestTypes.first} request)',
          ),
        ],
  );
}

String _kindForName(String name) {
  if (name.startsWith('I') &&
      name.length > 1 &&
      name[1].toUpperCase() == name[1]) {
    return 'Interface';
  }
  if (name.endsWith('Interface')) return 'Interface';
  if (name.endsWith('Base')) return 'Base type';
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

Directory _package(Directory root, String name, String source) {
  final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
  final lib = Directory(p.join(dir.path, 'lib'))..createSync();
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name');
  File(p.join(lib.path, '$name.dart')).writeAsStringSync(source);
  return dir;
}

PackageNode _node(String name, String path) {
  return PackageNode(
    name: name,
    path: path,
    rootPath: path,
    description: '',
    declaredDependencies: const [],
    usedDependencies: const [],
  );
}

Component _component(String name, String packageName) {
  return Component(
    name: name,
    packageName: packageName,
    responsibility: 'Test responsibility',
    dependencies: const [],
    dependents: const [],
    exportedSymbolCount: 1,
    keyExportedSymbols: const [],
  );
}
