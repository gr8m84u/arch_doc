import 'diagram_graph.dart';

class PlantUmlRenderer {
  String render(DiagramGraph graph) {
    final buffer = StringBuffer();
    buffer.writeln('@startuml');
    if (graph.direction == 'LR') {
      buffer.writeln('left to right direction');
    }
    for (final group in graph.groups) {
      buffer.writeln('package "${_escape(group.title)}" {');
      for (final node in group.nodes) {
        buffer.writeln(
          '  ${_nodeKeyword(node.kind)} "${_escape(node.label)}" as ${node.id}',
        );
      }
      buffer.writeln('}');
    }
    for (final edge in graph.edges) {
      final label = edge.label.isEmpty ? '' : ' : ${_escape(edge.label)}';
      buffer.writeln('${edge.from} --> ${edge.to}$label');
    }
    buffer.writeln('@enduml');
    return buffer.toString();
  }

  String _nodeKeyword(DiagramNodeKind kind) {
    return switch (kind) {
      DiagramNodeKind.package => 'component',
      DiagramNodeKind.component => 'component',
      DiagramNodeKind.interfaceType => 'interface',
      DiagramNodeKind.classType => 'class',
      DiagramNodeKind.model => 'class',
      DiagramNodeKind.contract => 'interface',
      DiagramNodeKind.unknown => 'rectangle',
    };
  }

  String _escape(String value) => value.replaceAll('"', r'\"');
}
