import 'package:test/test.dart';
import 'package:arch_doc/arch_doc.dart';

void main() {
  group('ResponsibilityExtractor', () {
    final extractor = ResponsibilityExtractor();

    test('extracts known responsibilities from package names and API', () {
      expect(
        extractor.extract(
          packageName: 'sample_jwt',
          description: '',
          publicSurface: [],
        ),
        'JWT token handling',
      );
      expect(
        extractor.extract(
          packageName: 'sample_identity',
          description: '',
          publicSurface: [],
        ),
        'Identity abstractions',
      );
      expect(
        extractor.extract(
          packageName: 'sample_windows_ffi',
          description: '',
          publicSurface: [],
        ),
        'Windows authentication implementation',
      );
      expect(
        extractor.extract(
          packageName: 'sample_models',
          description: '',
          publicSurface: [],
        ),
        'Shared domain models',
      );
      expect(
        extractor.extract(
          packageName: 'sample_config',
          description: '',
          publicSurface: [_declaration('JwtClaimNames')],
        ),
        'Configuration management',
      );
    });

    test('falls back to unknown responsibility', () {
      expect(
        extractor.extract(
          packageName: 'misc_tools',
          description: '',
          publicSurface: [],
        ),
        ResponsibilityExtractor.unknownResponsibility,
      );
    });
  });

  group('ComponentDiscovery', () {
    test('builds component graph with dependencies and dependents', () {
      final graph = ComponentDiscovery().discover(
        [
          _node('sample_models', usedDependencies: []),
          _node(
            'sample_jwt',
            usedDependencies: ['sample_jwt', 'sample_models'],
          ),
        ],
        {
          'sample_models': _api('sample_models', [_declaration('AuthClaims')]),
          'sample_jwt': _api('sample_jwt', [_declaration('JwtIssuer')]),
        },
      );

      final jwt = graph.components.singleWhere(
        (c) => c.packageName == 'sample_jwt',
      );
      final models = graph.components.singleWhere(
        (c) => c.packageName == 'sample_models',
      );

      expect(jwt.name, 'Sample JWT');
      expect(jwt.responsibility, 'JWT token handling');
      expect(jwt.dependencies, ['sample_models']);
      expect(jwt.dependents, isEmpty);

      expect(models.name, 'Sample Models');
      expect(models.dependencies, isEmpty);
      expect(models.dependents, ['sample_jwt']);
    });

    test('reports component warnings without failing discovery', () {
      final graph = ComponentDiscovery().discover(
        [_node('misc_tools')],
        {'misc_tools': _api('misc_tools', [])},
      );

      final component = graph.components.single;
      expect(component.warnings, [
        'Component without public API',
        'No dependencies detected',
        'No dependents detected in workspace',
        'Unknown responsibility',
      ]);
    });
  });

  group('ComponentMarkdownGenerator', () {
    test('generates deterministic markdown', () {
      final graph = ComponentGraph(
        components: [
          Component(
            name: 'Sample JWT',
            packageName: 'sample_jwt',
            responsibility: 'JWT token handling',
            dependencies: ['sample_models'],
            dependents: [],
            exportedSymbolCount: 2,
            keyExportedSymbols: [
              _declaration('JwtIssuer'),
              _declaration('JwtVerifier'),
            ],
            warnings: ['No dependents detected in workspace'],
          ),
        ],
      );

      expect(
        ComponentMarkdownGenerator(graph).generate().trim(),
        '''
<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->
# Components

## Sample JWT

Package: `sample_jwt`

Dependencies: `sample_models`

Dependents: None

Responsibility: JWT token handling

Warnings: No dependents detected in workspace

Public API summary:

- Exported symbol count: 2
- Key exported symbols: `JwtIssuer`, `JwtVerifier`
'''
            .trim(),
      );
    });
  });

  group('ComponentDiagramGenerator', () {
    test('generates deterministic component graph', () {
      final graph = ComponentGraph(
        components: [
          Component(
            name: 'Sample JWT',
            packageName: 'sample_jwt',
            responsibility: 'JWT token handling',
            dependencies: ['sample_models'],
            dependents: [],
            exportedSymbolCount: 1,
            keyExportedSymbols: [_declaration('JwtIssuer')],
          ),
          Component(
            name: 'Sample Models',
            packageName: 'sample_models',
            responsibility: 'Shared domain models',
            dependencies: [],
            dependents: ['sample_jwt'],
            exportedSymbolCount: 1,
            keyExportedSymbols: [_declaration('AuthClaims')],
          ),
        ],
      );

      expect(
        ComponentDiagramGenerator(graph).generate().trim(),
        '''
graph TD
  component_Sample_JWT["Sample JWT"]
  component_Sample_Models["Sample Models"]

  component_Sample_JWT --> component_Sample_Models
'''
            .trim(),
      );
    });

    test('generates deterministic PlantUML component graph', () {
      final graph = ComponentGraph(
        components: [
          Component(
            name: 'Sample JWT',
            packageName: 'sample_jwt',
            responsibility: 'JWT token handling',
            dependencies: ['sample_models'],
            dependents: [],
            exportedSymbolCount: 1,
            keyExportedSymbols: [_declaration('JwtIssuer')],
          ),
          Component(
            name: 'Sample Models',
            packageName: 'sample_models',
            responsibility: 'Shared domain models',
            dependencies: [],
            dependents: ['sample_jwt'],
            exportedSymbolCount: 1,
            keyExportedSymbols: [_declaration('AuthClaims')],
          ),
        ],
      );

      expect(
        ComponentDiagramGenerator(graph).generatePlantUml().trim(),
        '''
@startuml
package "Components" {
  component "Sample JWT" as component_Sample_JWT
  component "Sample Models" as component_Sample_Models
}
component_Sample_JWT --> component_Sample_Models
@enduml
'''
            .trim(),
      );
    });
  });
}

PackageNode _node(String name, {List<String> usedDependencies = const []}) {
  return PackageNode(
    name: name,
    path: 'packages/$name',
    description: '',
    declaredDependencies: [],
    usedDependencies: usedDependencies,
  );
}

PackageApi _api(String packageName, List<ApiDeclaration> publicSurface) {
  return PackageApi(
    packageName: packageName,
    description: '',
    publicSurface: publicSurface,
    internalPublicDeclarations: [],
  );
}

ApiDeclaration _declaration(String name) {
  return ApiDeclaration(
    name: name,
    kind: ApiDeclarationKind.classDeclaration,
    libraryPath: 'src/$name.dart',
  );
}
