import 'dart:io';

import 'package:path/path.dart' as p;

import '../component/component_diagram_generator.dart';
import '../component/component_discovery.dart';
import '../component/component_markdown_generator.dart';
import '../component/component_models.dart';
import '../config/arch_config.dart';
import '../contract/contract_analyzer.dart';
import '../contract/contract_markdown_generator.dart';
import '../contract/contract_models.dart';
import '../model/api_models.dart';
import '../narrative/architecture_narrative.dart';
import '../narrative/architecture_narrative_generator.dart';
import '../validation/arch_validator.dart';
import '../validation/architecture_violation.dart';
import '../validation/remediation_guide_generator.dart';
import '../validation/rules_v2_validator.dart';
import '../workspace/api_analyzer.dart';
import '../workspace/api_markdown_generator.dart';
import '../workspace/markdown_generator.dart';
import '../workspace/workspace_graph.dart';

enum ArchDocCommand { generate, validate }

class ArchitectureModel {
  final List<PackageNode> packages;
  final Map<String, PackageApi> api;
  final Map<String, String> apiMarkdown;
  final ComponentGraph components;
  final ComponentContractGraph contracts;
  final ArchitectureNarrative? narrative;
  final Map<String, Object?> metadata;

  ArchitectureModel({
    required this.packages,
    required this.api,
    required this.apiMarkdown,
    required this.components,
    required this.contracts,
    required this.narrative,
    required this.metadata,
  });

  Map<String, List<String>> get dependencies => {
        for (final package in packages)
          package.name: package.declaredDependencies.toList()..sort(),
      };
}

class ArchitectureEvaluation {
  final List<ArchitectureViolation> findings;
  final Map<String, int> validationSummary;
  final Map<String, int> riskSummary;

  ArchitectureEvaluation({
    required this.findings,
    required this.validationSummary,
    required this.riskSummary,
  });

  bool get hasErrors =>
      findings.any((finding) => finding.level == ViolationLevel.error);
}

class ArchDocOptions {
  final ArchDocCommand command;
  final String rootPath;
  final bool check;
  final DependencySource dependencySource;
  final String? configPath;

  ArchDocOptions({
    required this.command,
    required this.rootPath,
    this.check = false,
    this.dependencySource = DependencySource.declared,
    this.configPath,
  });
}

class ArchDocResult {
  final int exitCode;
  final List<String> stdout;
  final ArchitectureModel? model;
  final ArchitectureEvaluation? evaluation;

  ArchDocResult({
    required this.exitCode,
    required this.stdout,
    this.model,
    this.evaluation,
  });

  bool get success => exitCode == 0;
}

class ArchDocRunner {
  Future<ArchDocResult> run(ArchDocOptions options) async {
    final output = <String>[];
    final rootPath = options.rootPath;
    final configPath = discoverConfigPath(rootPath, options.configPath);

    ArchConfig? loadedConfig;
    if (configPath != null && File(configPath).existsSync()) {
      loadedConfig = ArchConfig.load(configPath);
    }
    if (options.configPath != null && loadedConfig == null) {
      output.add('Configuration file not found: ${options.configPath}');
      return ArchDocResult(exitCode: 1, stdout: output);
    }
    if (options.command == ArchDocCommand.validate && loadedConfig == null) {
      output.add('Configuration file not found.');
      output.add(
        'Create arch_doc.yaml in the workspace root or pass --config.',
      );
      output.add(
        r'Example: dart run arch_doc --config C:\path\to\arch_doc.yaml validate',
      );
      return ArchDocResult(exitCode: 1, stdout: output);
    }

    final analyzer = loadedConfig == null
        ? WorkspaceAnalyzer(rootPath)
        : WorkspaceAnalyzer.fromConfig(rootPath, loadedConfig);
    final analysis = await analyzer.analyzeWithFindings();

    switch (options.command) {
      case ArchDocCommand.generate:
        return _runGenerate(
          options: options,
          loadedConfig: loadedConfig,
          analysis: analysis,
          output: output,
        );
      case ArchDocCommand.validate:
        return _runValidate(
          options: options,
          loadedConfig: loadedConfig,
          configPath: configPath,
          analysis: analysis,
          output: output,
        );
    }
  }

  Future<ArchDocResult> _runGenerate({
    required ArchDocOptions options,
    required ArchConfig? loadedConfig,
    required WorkspaceAnalysisResult analysis,
    required List<String> output,
  }) async {
    final rootPath = options.rootPath;
    final config = loadedConfig;
    final outputConfig = config?.output ?? OutputConfig.defaults();

    if (analysis.hasErrors) {
      output.add('Architecture discovery failed.');
      output.add('');
      _addFindings(
        output,
        'Errors',
        analysis.findings,
        ViolationLevel.error,
        rootPath,
        outputConfig,
      );
      return ArchDocResult(exitCode: 1, stdout: output);
    }

    _addFindings(
      output,
      'Warnings',
      analysis.findings,
      ViolationLevel.warning,
      rootPath,
      outputConfig,
    );
    _addFindings(
      output,
      'Observations',
      analysis.findings,
      ViolationLevel.observation,
      rootPath,
      outputConfig,
    );

    final model = _buildModel(
      rootPath: rootPath,
      config: config,
      analysis: analysis,
    );
    final evaluation = _buildEvaluation(
      analysis: analysis,
      config: config,
      model: model,
    );
    final artifacts = _buildArtifacts(
      rootPath: rootPath,
      output: outputConfig,
      dependencySource: options.dependencySource,
      config: config,
      model: model,
      findings: evaluation.findings,
    );

    if (options.check) {
      final mismatch = _checkArtifacts(
        rootPath: rootPath,
        artifacts: artifacts,
        output: output,
      );
      if (mismatch) {
        output.add('');
        output.add('Architecture documentation is out of date.');
        output.add(r'Run "dart run arch_doc generate" to update.');
        return ArchDocResult(
          exitCode: 1,
          stdout: output,
          model: model,
          evaluation: evaluation,
        );
      }

      output.add('Architecture documentation is up to date.');
      return ArchDocResult(
        exitCode: 0,
        stdout: output,
        model: model,
        evaluation: evaluation,
      );
    }

    _writeArtifacts(rootPath: rootPath, artifacts: artifacts, output: output);
    return ArchDocResult(
      exitCode: 0,
      stdout: output,
      model: model,
      evaluation: evaluation,
    );
  }

  Future<ArchDocResult> _runValidate({
    required ArchDocOptions options,
    required ArchConfig? loadedConfig,
    required String? configPath,
    required WorkspaceAnalysisResult analysis,
    required List<String> output,
  }) async {
    final rootPath = options.rootPath;
    late ArchConfig config;
    try {
      config = loadedConfig ?? ArchConfig.load(configPath!);
    } catch (e) {
      output.add('Error loading configuration: $e');
      return ArchDocResult(exitCode: 1, stdout: output);
    }

    final model = _buildModel(
      rootPath: rootPath,
      config: config,
      analysis: analysis,
    );
    final evaluation = _buildEvaluation(
      analysis: analysis,
      config: config,
      model: model,
    );
    final findings = evaluation.findings;

    if (findings.isEmpty) {
      output.add('Architecture validation passed.');
    } else {
      output.add('Architecture validation completed with findings.');
      output.add('');
      _addFindings(
        output,
        'Errors',
        findings,
        ViolationLevel.error,
        rootPath,
        config.output,
      );
      _addFindings(
        output,
        'Warnings',
        findings,
        ViolationLevel.warning,
        rootPath,
        config.output,
      );
      _addFindings(
        output,
        'Observations',
        findings,
        ViolationLevel.observation,
        rootPath,
        config.output,
      );
    }

    return ArchDocResult(
      exitCode: evaluation.hasErrors ? 1 : 0,
      stdout: output,
      model: model,
      evaluation: evaluation,
    );
  }

  ArchitectureModel _buildModel({
    required String rootPath,
    required ArchConfig? config,
    required WorkspaceAnalysisResult analysis,
  }) {
    final packageApis = _analyzePackageApis(analysis.nodes);
    final apiMarkdown = <String, String>{};
    for (final entry in packageApis.entries) {
      apiMarkdown[entry.key] = ApiMarkdownGenerator(entry.value).generate();
    }

    final componentGraph = ComponentDiscovery().discover(
      analysis.nodes,
      packageApis,
    );
    final contractGraph = config == null
        ? ComponentContractGraph(
            contracts: const [],
            consumedContracts: const [],
            implementedContracts: const [],
            findings: const [],
          )
        : ContractAnalyzer().analyze(
            packages: analysis.nodes,
            componentGraph: componentGraph,
            config: config,
          );

    ArchitectureNarrative? narrative;
    if (config != null) {
      final findings = _buildFindings(
        analysis: analysis,
        config: config,
        nodes: analysis.nodes,
        packageApis: packageApis,
        componentGraph: componentGraph,
        contractGraph: contractGraph,
      );
      narrative = ArchitectureNarrativeGenerator(
        packages: analysis.nodes,
        componentGraph: componentGraph,
        config: config,
        packageApis: packageApis,
        findings: findings,
      ).generate();
    }

    return ArchitectureModel(
      packages: analysis.nodes,
      api: packageApis,
      apiMarkdown: apiMarkdown,
      components: componentGraph,
      contracts: contractGraph,
      narrative: narrative,
      metadata: {
        'rootPath': rootPath,
        'packageCount': analysis.nodes.length,
        'componentCount': componentGraph.components.length,
        'contractCount': contractGraph.contracts.length,
      },
    );
  }

  ArchitectureEvaluation _buildEvaluation({
    required WorkspaceAnalysisResult analysis,
    required ArchConfig? config,
    required ArchitectureModel model,
  }) {
    final findings = config == null
        ? analysis.findings.toList()
        : _buildFindings(
            analysis: analysis,
            config: config,
            nodes: model.packages,
            packageApis: model.api,
            componentGraph: model.components,
            contractGraph: model.contracts,
          );
    findings.sort(compareFindings);

    int count(ViolationLevel level) =>
        findings.where((finding) => finding.level == level).length;

    return ArchitectureEvaluation(
      findings: findings,
      validationSummary: {
        'errors': count(ViolationLevel.error),
        'warnings': count(ViolationLevel.warning),
        'observations': count(ViolationLevel.observation),
      },
      riskSummary: {
        'findings': findings.length,
        'warnings': count(ViolationLevel.warning),
        'observations': count(ViolationLevel.observation),
      },
    );
  }

  _GeneratedArtifacts _buildArtifacts({
    required String rootPath,
    required OutputConfig output,
    required DependencySource dependencySource,
    required ArchConfig? config,
    required ArchitectureModel model,
    required List<ArchitectureViolation> findings,
  }) {
    final packageGenerator = DocGenerator(
      model.packages,
      dependencySource: dependencySource,
    );
    final jsonContent = packageGenerator.generateJson();
    final mermaidContent = packageGenerator.generateMermaid();
    final packagesPlantUmlContent = packageGenerator.generatePlantUml();

    String? readmeContent;
    if (config != null) {
      readmeContent = MarkdownGenerator(
        nodes: model.packages,
        config: config,
        packageApis: model.api,
        narrativeHealth: model.narrative?.health,
        findings: findings,
        contractGraph: model.contracts,
        packageDiagramMermaid: mermaidContent,
      ).generate();
    }

    final componentsMarkdown = ComponentMarkdownGenerator(
      model.components,
      contractGraph: model.contracts,
      config: config,
    ).generate();
    final componentDiagramGenerator = ComponentDiagramGenerator(
      model.components,
    );
    final componentsMermaid = componentDiagramGenerator.generate();
    final componentsPlantUml = componentDiagramGenerator.generatePlantUml();
    final contractDocuments = config == null
        ? null
        : generateContractDocuments(
            graph: model.contracts,
            componentGraph: model.components,
            config: config,
          );

    final artifacts = _GeneratedArtifacts(
      apiDir: outputDir(rootPath, output, output.apiDir),
      componentContractsDir: outputDir(
        rootPath,
        output,
        output.componentContractsDir,
      ),
    );

    void add(
      String relativePath,
      String content, {
      bool printGenerated = true,
    }) {
      artifacts.files.add(
        _GeneratedFile(
          file: outputFile(rootPath, output, relativePath),
          content: content,
          printGenerated: printGenerated,
        ),
      );
    }

    if (readmeContent != null) add(output.readme, readmeContent);
    add(output.componentsReport, componentsMarkdown);
    add(output.componentsDiagram, componentsMermaid);
    add(output.componentsDiagramPlantUml, componentsPlantUml);
    if (model.narrative != null) {
      add(output.narrativeReport, model.narrative!.narrativeMarkdown);
      add(output.risksReport, model.narrative!.risksMarkdown);
    }
    add(output.remediationGuide, RemediationGuideGenerator().generate());
    if (contractDocuments != null) {
      add(output.contractsReport, contractDocuments.globalMarkdown);
      add(output.contractsDiagram, contractDocuments.globalMermaid);
      add(output.contractsDiagramPlantUml, contractDocuments.globalPlantUml);
      for (final entry in contractDocuments.componentMarkdownBySlug.entries) {
        artifacts.componentFiles.add(
          _GeneratedNamedFile(name: '${entry.key}.md', content: entry.value),
        );
      }
      for (final entry in contractDocuments.componentHldMermaidBySlug.entries) {
        artifacts.componentFiles.add(
          _GeneratedNamedFile(
            name: '${entry.key}.hld.mmd',
            content: entry.value,
          ),
        );
      }
      for (final entry
          in contractDocuments.componentHldPlantUmlBySlug.entries) {
        artifacts.componentFiles.add(
          _GeneratedNamedFile(
            name: '${entry.key}.hld.puml',
            content: entry.value,
          ),
        );
      }
      for (final entry in contractDocuments.componentLldMermaidBySlug.entries) {
        artifacts.componentFiles.add(
          _GeneratedNamedFile(
            name: '${entry.key}.lld.mmd',
            content: entry.value,
          ),
        );
      }
      for (final entry
          in contractDocuments.componentLldPlantUmlBySlug.entries) {
        artifacts.componentFiles.add(
          _GeneratedNamedFile(
            name: '${entry.key}.lld.puml',
            content: entry.value,
          ),
        );
      }
    }

    for (final entry in model.apiMarkdown.entries) {
      artifacts.apiFiles.add(
        _GeneratedNamedFile(name: '${entry.key}.md', content: entry.value),
      );
    }

    add(output.workspaceGraph, jsonContent, printGenerated: false);
    add(output.packagesDiagram, mermaidContent, printGenerated: false);
    add(
      output.packagesDiagramPlantUml,
      packagesPlantUmlContent,
      printGenerated: false,
    );

    return artifacts;
  }

  bool _checkArtifacts({
    required String rootPath,
    required _GeneratedArtifacts artifacts,
    required List<String> output,
  }) {
    var mismatch = false;

    for (final file in artifacts.files) {
      if (!_contentsMatch(file.file, file.content)) {
        output.add('MISMATCH: ${p.relative(file.file.path, from: rootPath)}');
        mismatch = true;
      }
    }

    for (final file in artifacts.componentFiles) {
      final target = File(
        p.join(artifacts.componentContractsDir.path, file.name),
      );
      if (!_contentsMatch(target, file.content)) {
        output.add('MISMATCH: ${p.relative(target.path, from: rootPath)}');
        mismatch = true;
      }
    }

    if (artifacts.componentContractsDir.existsSync()) {
      final expected =
          artifacts.componentFiles.map((file) => file.name).toSet();
      final existing = artifacts.componentContractsDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) {
        final ext = p.extension(file.path);
        return ext == '.md' || ext == '.mmd' || ext == '.puml';
      }).toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final file in existing) {
        if (!expected.contains(p.basename(file.path))) {
          output.add('ORPHAN: ${p.relative(file.path, from: rootPath)}');
          mismatch = true;
        }
      }
    }

    for (final file in artifacts.apiFiles) {
      final target = File(p.join(artifacts.apiDir.path, file.name));
      if (!_contentsMatch(target, file.content)) {
        output.add('MISMATCH: ${p.relative(target.path, from: rootPath)}');
        mismatch = true;
      }
    }

    if (artifacts.apiDir.existsSync()) {
      final expected = artifacts.apiFiles.map((file) => file.name).toSet();
      final existing = artifacts.apiDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.md')
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final file in existing) {
        if (!expected.contains(p.basename(file.path))) {
          output.add('ORPHAN: ${p.relative(file.path, from: rootPath)}');
          mismatch = true;
        }
      }
    }

    return mismatch;
  }

  void _writeArtifacts({
    required String rootPath,
    required _GeneratedArtifacts artifacts,
    required List<String> output,
  }) {
    for (final file in artifacts.files) {
      file.file.parent.createSync(recursive: true);
      file.file.writeAsStringSync(file.content);
      if (file.printGenerated) {
        output.add('Generated: ${p.relative(file.file.path, from: rootPath)}');
      }
    }

    artifacts.componentContractsDir.createSync(recursive: true);
    for (final file in artifacts.componentFiles) {
      final target = File(
        p.join(artifacts.componentContractsDir.path, file.name),
      );
      target.writeAsStringSync(file.content);
      output.add('Generated: ${p.relative(target.path, from: rootPath)}');
    }

    if (!artifacts.apiDir.existsSync()) {
      artifacts.apiDir.createSync(recursive: true);
    }
    for (final file in artifacts.apiFiles) {
      final target = File(p.join(artifacts.apiDir.path, file.name));
      target.writeAsStringSync(file.content);
      output.add('Generated: ${p.relative(target.path, from: rootPath)}');
    }

    for (final file in artifacts.files.where((file) => !file.printGenerated)) {
      output.add('Generated: ${p.relative(file.file.path, from: rootPath)}');
    }
  }

  bool _contentsMatch(File file, String expected) {
    if (!file.existsSync()) return false;
    final actual = file.readAsStringSync().replaceAll('\r\n', '\n');
    final target = expected.replaceAll('\r\n', '\n');
    return actual == target;
  }

  Map<String, PackageApi> _analyzePackageApis(List<PackageNode> nodes) {
    final apiAnalyzer = ApiAnalyzer();
    final packageApis = <String, PackageApi>{};
    for (final node in nodes) {
      final packageDir = Directory(node.rootPath);
      packageApis[node.name] = apiAnalyzer.analyze(
        packageDir,
        node.name,
        node.description,
      );
    }
    return packageApis;
  }

  List<ArchitectureViolation> _buildFindings({
    required WorkspaceAnalysisResult analysis,
    required ArchConfig config,
    required List<PackageNode> nodes,
    required Map<String, PackageApi> packageApis,
    required ComponentGraph componentGraph,
    required ComponentContractGraph contractGraph,
  }) {
    return <ArchitectureViolation>[
      ...analysis.findings,
      ...contractGraph.findings,
      ...ArchValidator(
        config: config,
        nodes: nodes,
        dependencySource: DependencySource.used,
      ).validate(),
      ...RulesV2Validator(
        config: config,
        packageApis: packageApis,
        componentGraph: componentGraph,
      ).validate(),
    ]..sort(compareFindings);
  }

  void _addFindings(
    List<String> output,
    String title,
    List<ArchitectureViolation> findings,
    ViolationLevel level,
    String rootPath,
    OutputConfig outputConfig,
  ) {
    final matching =
        findings.where((finding) => finding.level == level).toList();
    if (matching.isEmpty) return;

    output.add('$title:');
    final remediationPath = p
        .relative(
          outputFile(
            rootPath,
            outputConfig,
            outputConfig.remediationGuide,
          ).path,
          from: rootPath,
        )
        .replaceAll('\\', '/');
    for (final finding in matching) {
      output.add('- ${finding.reportLine}');
      output.add('  See: ${finding.remediationLink(remediationPath)}');
    }
    output.add('');
  }
}

String? discoverConfigPath(String rootPath, [String? explicitConfigPath]) {
  if (explicitConfigPath != null) return explicitConfigPath;

  final rootConfig = p.join(rootPath, 'arch_doc.yaml');
  if (File(rootConfig).existsSync()) return rootConfig;

  final legacyConfig = p.join(
    rootPath,
    'tools',
    'arch_doc',
    'config',
    'arch_doc.yaml',
  );
  if (File(legacyConfig).existsSync()) return legacyConfig;

  return null;
}

String defaultConfigPath(String rootPath) {
  return p.join(rootPath, 'arch_doc.yaml');
}

File outputFile(String rootPath, OutputConfig output, String relativePath) {
  return File(
    p.joinAll([
      rootPath,
      ...p.posix.split(output.root),
      ...p.posix.split(relativePath),
    ]),
  );
}

Directory outputDir(String rootPath, OutputConfig output, String relativePath) {
  return Directory(
    p.joinAll([
      rootPath,
      ...p.posix.split(output.root),
      ...p.posix.split(relativePath),
    ]),
  );
}

class _GeneratedArtifacts {
  final List<_GeneratedFile> files = [];
  final List<_GeneratedNamedFile> apiFiles = [];
  final List<_GeneratedNamedFile> componentFiles = [];
  final Directory apiDir;
  final Directory componentContractsDir;

  _GeneratedArtifacts({
    required this.apiDir,
    required this.componentContractsDir,
  });
}

class _GeneratedFile {
  final File file;
  final String content;
  final bool printGenerated;

  _GeneratedFile({
    required this.file,
    required this.content,
    required this.printGenerated,
  });
}

class _GeneratedNamedFile {
  final String name;
  final String content;

  _GeneratedNamedFile({required this.name, required this.content});
}
