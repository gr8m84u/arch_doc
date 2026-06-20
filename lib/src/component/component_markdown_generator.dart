import 'component_models.dart';
import '../contract/contract_markdown_generator.dart';
import '../contract/contract_models.dart';
import '../config/arch_config.dart';

class ComponentMarkdownGenerator {
  final ComponentGraph graph;
  final ComponentContractGraph? contractGraph;
  final ArchConfig? config;

  ComponentMarkdownGenerator(this.graph, {this.contractGraph, this.config});

  String generate() {
    final buffer = StringBuffer();
    buffer.writeln('<!-- GENERATED FILE - DO NOT EDIT MANUALLY -->');
    buffer.writeln('# Components');
    buffer.writeln();

    final components = graph.components.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final component in components) {
      buffer.writeln('## ${component.name}');
      buffer.writeln();
      buffer.writeln('Package: `${component.packageName}`');
      buffer.writeln();
      buffer.writeln(
        'Dependencies: ${_formatPackages(component.dependencies)}',
      );
      buffer.writeln();
      buffer.writeln('Dependents: ${_formatPackages(component.dependents)}');
      buffer.writeln();
      buffer.writeln('Responsibility: ${component.responsibility}');
      buffer.writeln();
      buffer.writeln('Warnings: ${_formatWarnings(component.warnings)}');
      buffer.writeln();
      buffer.writeln('Public API summary:');
      buffer.writeln();
      buffer.writeln(
        '- Exported symbol count: ${component.exportedSymbolCount}',
      );
      buffer.writeln('- Key exported symbols: ${_formatSymbols(component)}');
      if (contractGraph != null && config != null) {
        final ownedContracts = contractGraph!.contracts
            .where((contract) => contract.ownerComponent == component.name)
            .toList();
        final behaviorContractCount = ownedContracts
            .where((contract) => contract.isBehaviorContract)
            .length;
        final supportingDomainTypeCount = ownedContracts
            .where((contract) => contract.isSupportingDomainType)
            .length;
        final slug = componentContractSlug(component);
        final base = config!.output.componentContractsDir;
        buffer.writeln();
        buffer.writeln('Contracts:');
        buffer.writeln();
        buffer.writeln('- Behavior contracts: $behaviorContractCount');
        buffer.writeln('- Supporting/domain types: $supportingDomainTypeCount');
        buffer.writeln('- Docs: [$slug.md](../$base/$slug.md)');
        buffer.writeln(
          '- HLD diagram: [$slug.hld.mmd](../$base/$slug.hld.mmd)',
        );
        buffer.writeln(
          '- HLD PlantUML: [$slug.hld.puml](../$base/$slug.hld.puml)',
        );
        buffer.writeln(
          '- LLD diagram: [$slug.lld.mmd](../$base/$slug.lld.mmd)',
        );
        buffer.writeln(
          '- LLD PlantUML: [$slug.lld.puml](../$base/$slug.lld.puml)',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _formatPackages(List<String> packages) {
    if (packages.isEmpty) return 'None';
    final sorted = packages.toList()..sort();
    return sorted.map((package) => '`$package`').join(', ');
  }

  String _formatWarnings(List<String> warnings) {
    if (warnings.isEmpty) return 'None';
    final sorted = warnings.toList()..sort();
    return sorted.join('; ');
  }

  String _formatSymbols(Component component) {
    if (component.keyExportedSymbols.isEmpty) return 'None';
    return component.keyExportedSymbols
        .map((symbol) => '`${symbol.name}`')
        .join(', ');
  }
}
