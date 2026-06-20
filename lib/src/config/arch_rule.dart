class ArchRule {
  final String name;
  final String fromLayer;
  final List<String> forbiddenLayers;

  ArchRule({
    required this.name,
    required this.fromLayer,
    required this.forbiddenLayers,
  });
}
