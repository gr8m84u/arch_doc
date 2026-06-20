import 'component_models.dart';
import '../diagram/diagram_graph.dart';
import '../diagram/plantuml_renderer.dart';

class ComponentDiagramGenerator {
  final ComponentGraph graph;

  ComponentDiagramGenerator(this.graph);

  String generate() {
    final buffer = StringBuffer();
    buffer.writeln('graph TD');

    final components = graph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final byPackage = {
      for (final component in components) component.packageName: component,
    };

    for (final component in components) {
      buffer.writeln(
        '  ${_nodeId(component)}["${_escapeLabel(component.name)}"]',
      );
    }

    buffer.writeln();

    final edges = <String>[];
    for (final component in components) {
      final dependencies = component.dependencies.toList()..sort();
      for (final dependency in dependencies) {
        final target = byPackage[dependency];
        if (target == null) continue;
        edges.add('  ${_nodeId(component)} --> ${_nodeId(target)}');
      }
    }

    edges.sort();
    for (final edge in edges) {
      buffer.writeln(edge);
    }

    return buffer.toString();
  }

  String generatePlantUml() {
    final components = graph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final byPackage = {
      for (final component in components) component.packageName: component,
    };
    final edges = <DiagramEdge>[];
    for (final component in components) {
      final dependencies = component.dependencies.toList()..sort();
      for (final dependency in dependencies) {
        final target = byPackage[dependency];
        if (target == null) continue;
        edges.add(DiagramEdge(from: _nodeId(component), to: _nodeId(target)));
      }
    }

    return PlantUmlRenderer().render(
      DiagramGraph(
        direction: 'TD',
        groups: [
          DiagramGroup(
            title: 'Components',
            nodes: [
              for (final component in components)
                DiagramNode(
                  id: _nodeId(component),
                  label: component.name,
                  kind: DiagramNodeKind.component,
                ),
            ],
          ),
        ],
        edges: edges,
      ),
    );
  }

  String _nodeId(Component component) {
    final sanitized = component.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'component_$sanitized';
  }

  String _escapeLabel(String label) {
    return label.replaceAll('"', r'\"');
  }
}
