class PackageApi {
  final String packageName;
  final String description;
  final List<ApiDeclaration> publicSurface;
  final List<ApiDeclaration> internalPublicDeclarations;
  final List<String> warnings;

  PackageApi({
    required this.packageName,
    required this.description,
    required this.publicSurface,
    required this.internalPublicDeclarations,
    this.warnings = const [],
  });
}

class ApiDeclaration {
  final String name;
  final ApiDeclarationKind kind;
  final String libraryPath;
  final bool isAbstract;

  ApiDeclaration({
    required this.name,
    required this.kind,
    required this.libraryPath,
    this.isAbstract = false,
  });

  String get key => '$libraryPath|${kind.name}|$name';
}

enum ApiDeclarationKind {
  classDeclaration('Class'),
  enumDeclaration('Enum'),
  extensionDeclaration('Extension'),
  mixinDeclaration('Mixin'),
  typedefDeclaration('Typedef');

  final String label;
  const ApiDeclarationKind(this.label);
}
