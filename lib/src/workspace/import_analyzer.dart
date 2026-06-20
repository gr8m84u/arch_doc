import 'dart:io';
import 'package:path/path.dart' as p;

class ImportAnalyzer {
  // Simpler regex to avoid escaping issues in complex raw strings
  static final _importRegex = RegExp(
    r"^(import|export|part)\s+['" + '"' + r"]package:([^/]+)/",
    multiLine: true,
  );

  Set<String> analyze(Directory libDir) {
    if (!libDir.existsSync()) return {};

    final usedPackages = <String>{};

    try {
      for (final entity in libDir.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final fileName = p.basename(entity.path);
        if (_isGenerated(fileName, entity.path)) continue;

        final content = entity.readAsStringSync();
        final matches = _importRegex.allMatches(content);
        for (final match in matches) {
          final packageName = match.group(2);
          if (packageName != null) {
            usedPackages.add(packageName);
          }
        }
      }
    } catch (e) {
      // Log or handle error
    }

    return usedPackages;
  }

  bool _isGenerated(String fileName, String filePath) {
    if (fileName.endsWith('.g.dart') ||
        fileName.endsWith('.freezed.dart') ||
        fileName.endsWith('.config.dart')) {
      return true;
    }

    final normalizedPath = filePath.replaceAll('\\', '/');
    if (normalizedPath.contains('/generated/')) {
      return true;
    }

    return false;
  }
}
