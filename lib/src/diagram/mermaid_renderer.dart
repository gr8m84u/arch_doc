import 'diagram_graph.dart';

class MermaidRenderer {
  String render(DiagramGraph graph) {
    final buffer = StringBuffer();
    buffer.writeln('flowchart ${graph.direction}');
    for (final group in graph.groups) {
      buffer.writeln('  subgraph ${group.title}');
      for (final node in group.nodes) {
        buffer.writeln('    ${node.id}["${_escape(node.label)}"]');
      }
      buffer.writeln('  end');
    }
    for (final edge in graph.edges) {
      if (edge.label.isEmpty) {
        buffer.writeln('  ${edge.from} --> ${edge.to}');
      } else {
        buffer.writeln('  ${edge.from} -->|${_escape(edge.label)}| ${edge.to}');
      }
    }
    return buffer.toString();
  }

  String _escape(String value) => value.replaceAll('"', r'\"');
}
