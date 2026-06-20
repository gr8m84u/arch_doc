class DiagramGraph {
  final String direction;
  final List<DiagramGroup> groups;
  final List<DiagramEdge> edges;

  DiagramGraph({
    required this.direction,
    required List<DiagramGroup> groups,
    required List<DiagramEdge> edges,
  })  : groups = _sortedGroups(groups),
        edges = _sortedEdges(edges);
}

class DiagramGroup {
  final String title;
  final List<DiagramNode> nodes;

  DiagramGroup({required this.title, required List<DiagramNode> nodes})
      : nodes = _sortedNodes(nodes);
}

class DiagramNode {
  final String id;
  final String label;
  final DiagramNodeKind kind;

  DiagramNode({
    required this.id,
    required this.label,
    this.kind = DiagramNodeKind.unknown,
  });
}

class DiagramEdge {
  final String from;
  final String to;
  final String label;

  DiagramEdge({required this.from, required this.to, this.label = ''});
}

enum DiagramNodeKind {
  package,
  component,
  interfaceType,
  classType,
  model,
  contract,
  unknown,
}

List<DiagramGroup> _sortedGroups(List<DiagramGroup> groups) {
  final unique = <String, DiagramGroup>{};
  for (final group in groups) {
    if (group.nodes.isEmpty) continue;
    unique[group.title] = group;
  }
  return unique.values.toList();
}

List<DiagramNode> _sortedNodes(List<DiagramNode> nodes) {
  final unique = <String, DiagramNode>{};
  for (final node in nodes) {
    unique[node.id] = node;
  }
  return unique.values.toList()..sort(_compareNodes);
}

List<DiagramEdge> _sortedEdges(List<DiagramEdge> edges) {
  final unique = <String, DiagramEdge>{};
  for (final edge in edges) {
    unique['${edge.from}\n${edge.to}\n${edge.label}'] = edge;
  }
  return unique.values.toList()..sort(_compareEdges);
}

int _compareNodes(DiagramNode a, DiagramNode b) {
  final label = a.label.compareTo(b.label);
  if (label != 0) return label;
  return a.id.compareTo(b.id);
}

int _compareEdges(DiagramEdge a, DiagramEdge b) {
  final from = a.from.compareTo(b.from);
  if (from != 0) return from;
  final to = a.to.compareTo(b.to);
  if (to != 0) return to;
  return a.label.compareTo(b.label);
}
