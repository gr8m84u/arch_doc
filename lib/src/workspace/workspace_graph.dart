import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../config/arch_config.dart';
import '../diagram/diagram_graph.dart';
import '../diagram/plantuml_renderer.dart';
import '../validation/architecture_violation.dart';
import 'import_analyzer.dart';

enum DependencySource { declared, used }

enum PackageSource { local, externalPath }

class PackageNode {
  final String name;
  final String path;
  final String rootPath;
  final String relativePath;
  final bool isExternal;
  final String sourceRootLabel;
  final String description;
  final List<String> declaredDependencies;
  final List<String> usedDependencies;
  final List<String> devDependencies;
  final List<String> dependencyOverrides;

  PackageNode({
    required this.name,
    required String path,
    String? rootPath,
    String? relativePath,
    this.isExternal = false,
    String? sourceRootLabel,
    required this.description,
    required this.declaredDependencies,
    required this.usedDependencies,
    this.devDependencies = const [],
    this.dependencyOverrides = const [],
  })  : path = path.replaceAll('\\', '/'),
        rootPath = rootPath ?? path,
        relativePath = (relativePath ?? path).replaceAll('\\', '/'),
        sourceRootLabel =
            sourceRootLabel ?? (isExternal ? 'external path' : 'local');

  PackageSource get source =>
      isExternal ? PackageSource.externalPath : PackageSource.local;

  List<String> get unusedDeclaredDependencies {
    return declaredDependencies
        .where((d) => !usedDependencies.contains(d))
        .toList()
      ..sort();
  }

  List<String> get missingDeclaredDependencies {
    return usedDependencies
        .where((u) => !declaredDependencies.contains(u))
        .toList()
      ..sort();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'packagePath': relativePath,
        'isExternal': isExternal,
        'source': isExternal ? 'external_path' : 'local',
        'sourceRootLabel': sourceRootLabel,
        'description': description,
        'declaredDependencies': declaredDependencies,
        'usedDependencies': usedDependencies,
        'unusedDeclaredDependencies': unusedDeclaredDependencies,
        'missingDeclaredDependencies': missingDeclaredDependencies,
      };
}

class WorkspaceAnalysisResult {
  final List<PackageNode> nodes;
  final List<ArchitectureViolation> findings;

  WorkspaceAnalysisResult({required this.nodes, this.findings = const []});

  bool get hasErrors =>
      findings.any((finding) => finding.level == ViolationLevel.error);
}

class WorkspaceAnalyzer {
  final String rootPath;
  final bool includeExternalPathPackages;
  final int maxExternalDepth;
  final Map<String, String> externalPackageLabels;
  final List<String> excludedPackages;
  final List<String> excludePatterns;

  WorkspaceAnalyzer(
    String rootPath, {
    this.includeExternalPathPackages = false,
    this.maxExternalDepth = 2,
    this.externalPackageLabels = const {},
    List<String> excludedPackages = const [],
    List<String>? excludePatterns,
  })  : rootPath = _canonicalPath(rootPath),
        excludedPackages = excludedPackages,
        excludePatterns =
            excludePatterns ?? WorkspaceDiscoveryConfig.defaultExcludedPaths;

  factory WorkspaceAnalyzer.fromConfig(String rootPath, ArchConfig config) {
    return WorkspaceAnalyzer(
      rootPath,
      includeExternalPathPackages:
          config.workspaceDiscovery.includeExternalPathPackages,
      maxExternalDepth: config.workspaceDiscovery.maxExternalDepth,
      externalPackageLabels: config.workspaceDiscovery.externalPackageLabels,
      excludedPackages: config.excludedPackages,
      excludePatterns: config.excludedPaths,
    );
  }

  Future<List<PackageNode>> analyze() async {
    return (await analyzeWithFindings()).nodes;
  }

  Future<WorkspaceAnalysisResult> analyzeWithFindings() async {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      return WorkspaceAnalysisResult(nodes: const []);
    }

    final importAnalyzer = ImportAnalyzer();
    final visitedPaths = <String>{};
    final nodesByPath = <String, PackageNode>{};
    final findings = <ArchitectureViolation>[];

    await _discoverLocalPackages(
      rootDir,
      importAnalyzer,
      visitedPaths,
      nodesByPath,
    );

    if (includeExternalPathPackages) {
      final localNodes = nodesByPath.values
          .where((node) => !node.isExternal)
          .toList()
        ..sort((a, b) => a.rootPath.compareTo(b.rootPath));
      final workspaceExternalNodes = _discoverRootWorkspaceEntries(
        rootDir,
        importAnalyzer,
        visitedPaths,
        nodesByPath,
        findings,
      );

      for (final node in localNodes) {
        _discoverExternalDependencies(
          Directory(node.rootPath),
          importAnalyzer,
          visitedPaths,
          nodesByPath,
          findings,
          remainingDepth: maxExternalDepth,
        );
      }
      if (maxExternalDepth > 0) {
        for (final node in workspaceExternalNodes) {
          _discoverExternalDependencies(
            Directory(node.rootPath),
            importAnalyzer,
            visitedPaths,
            nodesByPath,
            findings,
            remainingDepth: maxExternalDepth - 1,
          );
        }
      }
    }

    final nodes = nodesByPath.values
        .where((node) => !excludedPackages.contains(node.name))
        .toList()
      ..sort(_compareNodes);
    findings.addAll(_findDuplicatePackageNames(nodes));
    findings.sort(_compareFindings);

    return WorkspaceAnalysisResult(nodes: nodes, findings: findings);
  }

  Future<void> _discoverLocalPackages(
    Directory rootDir,
    ImportAnalyzer importAnalyzer,
    Set<String> visitedPaths,
    Map<String, PackageNode> nodesByPath,
  ) async {
    final packageDirs = <Directory>[];
    final rootPubspec = File(p.join(rootDir.path, 'pubspec.yaml'));
    if (rootPubspec.existsSync()) {
      packageDirs.add(rootDir);
    }

    await for (final entity in rootDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! Directory) continue;
      if (_isExcludedPath(entity.path)) continue;

      final pubspecFile = File(p.join(entity.path, 'pubspec.yaml'));
      if (pubspecFile.existsSync()) {
        packageDirs.add(entity);
      }
    }

    packageDirs.sort((a, b) => a.path.compareTo(b.path));
    for (final dir in packageDirs) {
      _addPackage(
        dir,
        importAnalyzer,
        visitedPaths,
        nodesByPath,
        isExternal: false,
      );
    }
  }

  List<PackageNode> _discoverRootWorkspaceEntries(
    Directory rootDir,
    ImportAnalyzer importAnalyzer,
    Set<String> visitedPaths,
    Map<String, PackageNode> nodesByPath,
    List<ArchitectureViolation> findings,
  ) {
    final addedNodes = <PackageNode>[];
    final pubspec = _loadPubspec(rootDir);
    final workspace = pubspec?['workspace'] as YamlList?;
    if (workspace == null) return addedNodes;

    final entries = workspace.cast<String>().toList()..sort();
    for (final entry in entries) {
      final targetPath = _resolvePath(rootDir.path, entry);
      if (!_isExternalPath(targetPath)) continue;

      final added = _addExternalPackageByPath(
        originalPath: entry,
        targetPath: targetPath,
        importAnalyzer: importAnalyzer,
        visitedPaths: visitedPaths,
        nodesByPath: nodesByPath,
        findings: findings,
      );
      if (added != null) addedNodes.add(added);
    }
    return addedNodes;
  }

  void _discoverExternalDependencies(
    Directory packageDir,
    ImportAnalyzer importAnalyzer,
    Set<String> visitedPaths,
    Map<String, PackageNode> nodesByPath,
    List<ArchitectureViolation> findings, {
    required int remainingDepth,
  }) {
    if (remainingDepth < 0) return;

    final pubspec = _loadPubspec(packageDir);
    if (pubspec == null) return;

    final externalPaths = [
      ..._extractPathDependencies(pubspec, 'dependencies'),
      ..._extractPathDependencies(pubspec, 'dependency_overrides'),
    ]..sort((a, b) => a.path.compareTo(b.path));

    for (final dep in externalPaths) {
      final targetPath = _resolvePath(packageDir.path, dep.path);
      if (!_isExternalPath(targetPath)) continue;

      final added = _addExternalPackageByPath(
        originalPath: dep.path,
        targetPath: targetPath,
        importAnalyzer: importAnalyzer,
        visitedPaths: visitedPaths,
        nodesByPath: nodesByPath,
        findings: findings,
      );
      if (added != null && remainingDepth > 0) {
        _discoverExternalDependencies(
          Directory(added.rootPath),
          importAnalyzer,
          visitedPaths,
          nodesByPath,
          findings,
          remainingDepth: remainingDepth - 1,
        );
      }
    }
  }

  PackageNode? _addExternalPackageByPath({
    required String originalPath,
    required String targetPath,
    required ImportAnalyzer importAnalyzer,
    required Set<String> visitedPaths,
    required Map<String, PackageNode> nodesByPath,
    required List<ArchitectureViolation> findings,
  }) {
    final dir = Directory(targetPath);
    final pubspec = File(p.join(targetPath, 'pubspec.yaml'));
    if (!dir.existsSync() || !pubspec.existsSync()) {
      findings.add(
        _discoveryFinding(
          ruleName: 'external_path_package_not_found',
          subject: originalPath,
          reason: 'External path package not found: $originalPath',
          level: ViolationLevel.warning,
        ),
      );
      return null;
    }

    return _addPackage(
      dir,
      importAnalyzer,
      visitedPaths,
      nodesByPath,
      isExternal: true,
      originalExternalPath: originalPath,
    );
  }

  PackageNode? _addPackage(
    Directory packageDir,
    ImportAnalyzer importAnalyzer,
    Set<String> visitedPaths,
    Map<String, PackageNode> nodesByPath, {
    required bool isExternal,
    String? originalExternalPath,
  }) {
    final packagePath = _canonicalPath(packageDir.path);
    if (visitedPaths.contains(packagePath)) {
      return nodesByPath[packagePath];
    }
    visitedPaths.add(packagePath);

    final pubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    final node = _parsePubspec(
      pubspecFile,
      Directory(packagePath),
      importAnalyzer,
      isExternal: isExternal,
      originalExternalPath: originalExternalPath,
    );
    if (node == null) return null;
    nodesByPath[packagePath] = node;
    return node;
  }

  PackageNode? _parsePubspec(
    File file,
    Directory packageDir,
    ImportAnalyzer importAnalyzer, {
    required bool isExternal,
    String? originalExternalPath,
  }) {
    try {
      final yaml = _loadPubspec(packageDir);
      if (yaml == null) return null;

      final name = yaml['name'] as String?;
      if (name == null) return null;

      final description = (yaml['description'] as String?) ?? '';
      final packagePath = _canonicalPath(packageDir.path);
      final readablePath = isExternal
          ? _readablePackagePath(
              packagePath,
              originalExternalPath: originalExternalPath,
            )
          : _normalizeRelative(p.relative(packagePath, from: rootPath));

      final libDir = Directory(p.join(packageDir.path, 'lib'));
      final used = importAnalyzer.analyze(libDir).toList()..sort();

      return PackageNode(
        name: name,
        path: readablePath,
        rootPath: packagePath,
        relativePath: readablePath,
        isExternal: isExternal,
        sourceRootLabel: isExternal
            ? _externalLabel(packagePath, originalExternalPath)
            : 'local',
        description: description,
        declaredDependencies: _extractDependencyNames(yaml, 'dependencies'),
        usedDependencies: used,
        devDependencies: _extractDependencyNames(yaml, 'dev_dependencies'),
        dependencyOverrides: _extractDependencyNames(
          yaml,
          'dependency_overrides',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  YamlMap? _loadPubspec(Directory packageDir) {
    final file = File(p.join(packageDir.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = loadYaml(file.readAsStringSync());
    return yaml is YamlMap ? yaml : null;
  }

  List<String> _extractDependencyNames(YamlMap yaml, String key) {
    final deps = yaml[key] as YamlMap?;
    if (deps == null) return [];

    final list = <String>[];
    deps.forEach((k, v) {
      if (v is YamlMap && v.containsKey('path')) {
        list.add(k as String);
      }
    });
    list.sort();
    return list;
  }

  List<_PathDependency> _extractPathDependencies(YamlMap yaml, String key) {
    final deps = yaml[key] as YamlMap?;
    if (deps == null) return [];

    final list = <_PathDependency>[];
    deps.forEach((k, v) {
      if (v is YamlMap && v['path'] is String) {
        list.add(_PathDependency(name: k as String, path: v['path'] as String));
      }
    });
    return list;
  }

  List<ArchitectureViolation> _findDuplicatePackageNames(
    List<PackageNode> nodes,
  ) {
    final byName = <String, List<PackageNode>>{};
    for (final node in nodes) {
      byName.putIfAbsent(node.name, () => []).add(node);
    }

    final findings = <ArchitectureViolation>[];
    final names = byName.keys.toList()..sort();
    for (final name in names) {
      final matches = byName[name]!;
      final paths = matches.map((node) => node.rootPath).toSet().toList()
        ..sort();
      if (paths.length < 2) continue;
      findings.add(
        _discoveryFinding(
          ruleName: 'duplicate_package_name',
          subject: name,
          reason:
              'Duplicate package name found: $name; paths: ${paths.join(', ')}',
          level: ViolationLevel.error,
        ),
      );
    }
    return findings;
  }

  ArchitectureViolation _discoveryFinding({
    required String ruleName,
    required String subject,
    required String reason,
    required ViolationLevel level,
  }) {
    return ArchitectureViolation(
      ruleName: ruleName,
      packageName: subject,
      dependencyName: 'N/A',
      reason: reason,
      level: level,
      category: 'discovery',
      subject: subject,
      isRisk: level == ViolationLevel.error,
    );
  }

  bool _isExcludedPath(String absolutePath) {
    final relative = _normalizeRelative(
      p.relative(absolutePath, from: rootPath),
    );
    final segments = p.posix.split(relative);
    if (segments.any((segment) => segment.startsWith('.'))) return true;

    for (final pattern in excludePatterns) {
      final normalized = pattern.replaceAll('\\', '/');
      if (normalized.startsWith('**/') && normalized.endsWith('/**')) {
        final segment = normalized.substring(3, normalized.length - 3);
        if (segments.contains(segment)) return true;
      }
      if (relative == normalized || relative.startsWith('$normalized/')) {
        return true;
      }
      if (segments.contains(normalized)) return true;
      if (normalized.endsWith('/**')) {
        final prefix = normalized.substring(0, normalized.length - 3);
        if (relative == prefix || relative.startsWith('$prefix/')) return true;
      }
    }
    return false;
  }

  String _resolvePath(String fromDir, String path) {
    return _canonicalPath(p.isAbsolute(path) ? path : p.join(fromDir, path));
  }

  bool _isExternalPath(String absolutePath) {
    return !_sameOrWithin(rootPath, absolutePath);
  }

  String _readablePackagePath(
    String absolutePath, {
    String? originalExternalPath,
  }) {
    final label = _labelFor(absolutePath, originalExternalPath);
    if (label != null) return label;
    return _normalizeRelative(p.relative(absolutePath, from: rootPath));
  }

  String _externalLabel(String absolutePath, String? originalExternalPath) {
    return _labelFor(absolutePath, originalExternalPath) ?? 'external path';
  }

  String? _labelFor(String absolutePath, String? originalExternalPath) {
    if (originalExternalPath != null &&
        externalPackageLabels.containsKey(originalExternalPath)) {
      return externalPackageLabels[originalExternalPath];
    }
    for (final entry in externalPackageLabels.entries) {
      final keyPath = _resolvePath(rootPath, entry.key);
      if (keyPath == absolutePath) return entry.value;
    }
    return null;
  }

  static String _canonicalPath(String path) {
    final absolute = p.normalize(p.absolute(path));
    final type = FileSystemEntity.typeSync(absolute, followLinks: true);
    if (type != FileSystemEntityType.notFound) {
      return Directory(absolute).resolveSymbolicLinksSync();
    }
    return absolute;
  }

  static bool _sameOrWithin(String parent, String child) {
    final normalizedParent = _normalizeCase(_canonicalPath(parent));
    final normalizedChild = _normalizeCase(_canonicalPath(child));
    return normalizedChild == normalizedParent ||
        p.isWithin(normalizedParent, normalizedChild);
  }

  static String _normalizeCase(String value) {
    if (Platform.isWindows) return value.toLowerCase();
    return value;
  }

  static String _normalizeRelative(String path) {
    return path.replaceAll('\\', '/');
  }
}

class DocGenerator {
  final List<PackageNode> nodes;
  final DependencySource dependencySource;

  DocGenerator(this.nodes, {this.dependencySource = DependencySource.declared});

  String generateJson() {
    final list = nodes.map((e) => e.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(list) + '\n';
  }

  String generateMermaid() {
    final buffer = StringBuffer();
    buffer.writeln('graph TD');

    for (final node in nodes) {
      final id = node.name;
      final desc = node.isExternal ? 'external path' : node.description;
      final escapedDesc = desc.replaceAll('"', '\\"');
      buffer.writeln('  $id["$id<br/><small>$escapedDesc</small>"]');
    }

    buffer.writeln();

    final knownPackageNames = nodes.map((n) => n.name).toSet();

    for (final node in nodes) {
      final deps = dependencySource == DependencySource.declared
          ? node.declaredDependencies
          : node.usedDependencies;

      for (final dep in deps) {
        if (knownPackageNames.contains(dep)) {
          buffer.writeln('  ${node.name} --> $dep');
        }
      }
    }

    return buffer.toString();
  }

  String generatePlantUml() {
    final knownPackageNames = nodes.map((n) => n.name).toSet();
    final edges = <DiagramEdge>[];
    for (final node in nodes) {
      final deps = dependencySource == DependencySource.declared
          ? node.declaredDependencies
          : node.usedDependencies;
      for (final dep in deps) {
        if (knownPackageNames.contains(dep)) {
          edges.add(
            DiagramEdge(from: _packageId(node.name), to: _packageId(dep)),
          );
        }
      }
    }

    return PlantUmlRenderer().render(
      DiagramGraph(
        direction: 'TD',
        groups: [
          DiagramGroup(
            title: 'Packages',
            nodes: [
              for (final node in nodes)
                DiagramNode(
                  id: _packageId(node.name),
                  label: node.name,
                  kind: DiagramNodeKind.package,
                ),
            ],
          ),
        ],
        edges: edges,
      ),
    );
  }

  String _packageId(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

class _PathDependency {
  final String name;
  final String path;

  _PathDependency({required this.name, required this.path});
}

int _compareNodes(PackageNode a, PackageNode b) {
  final name = a.name.compareTo(b.name);
  if (name != 0) return name;
  return a.rootPath.compareTo(b.rootPath);
}

int _compareFindings(ArchitectureViolation a, ArchitectureViolation b) {
  final level = a.level.index.compareTo(b.level.index);
  if (level != 0) return level;
  final code = a.code.compareTo(b.code);
  if (code != 0) return code;
  final subject = a.subject.compareTo(b.subject);
  if (subject != 0) return subject;
  return a.reason.compareTo(b.reason);
}
