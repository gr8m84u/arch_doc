import '../model/api_models.dart';

class ApiMarkdownGenerator {
  final PackageApi api;

  ApiMarkdownGenerator(this.api);

  String generate() {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Public API Summary: ${api.packageName}');
    buffer.writeln();
    buffer.writeln(api.description);
    buffer.writeln();

    if (api.warnings.isNotEmpty) {
      buffer.writeln('## Warnings');
      buffer.writeln();
      for (final warning in api.warnings) {
        buffer.writeln('- $warning');
      }
      buffer.writeln();
    }

    _writeDeclarations(buffer, 'Public Surface', api.publicSurface);
    _writeDeclarations(
      buffer,
      'Internal Public Declarations',
      api.internalPublicDeclarations,
    );

    buffer.writeln('## Known limitations');
    buffer.writeln();
    buffer.writeln('- Conditional exports not yet supported.');
    buffer.writeln('- Methods and comments are not analyzed.');
    buffer.writeln();

    return buffer.toString();
  }

  void _writeDeclarations(
    StringBuffer buffer,
    String title,
    List<ApiDeclaration> declarations,
  ) {
    buffer.writeln('## $title');
    buffer.writeln();
    if (declarations.isEmpty) {
      buffer.writeln('None');
      buffer.writeln();
      return;
    }

    for (final declaration in declarations) {
      final abstractSuffix = declaration.isAbstract ? ' (abstract)' : '';
      buffer.writeln(
        '- `${declaration.name}` (${declaration.kind.label}, `${declaration.libraryPath}`)$abstractSuffix',
      );
    }
    buffer.writeln();
  }
}
