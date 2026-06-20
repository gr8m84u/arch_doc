import 'finding_definition.dart';

enum ViolationLevel { error, warning, observation }

class ArchitectureViolation {
  final String ruleName;
  final String packageName;
  final String dependencyName;
  final String reason;
  final ViolationLevel level;
  final String category;
  final String subject;
  final bool isRisk;
  final String? findingCode;

  ArchitectureViolation({
    required this.ruleName,
    required this.packageName,
    required this.dependencyName,
    required this.reason,
    this.level = ViolationLevel.error,
    this.category = 'architecture',
    String? subject,
    this.isRisk = false,
    this.findingCode,
  }) : subject = subject ?? packageName;

  ArchitectureViolation copyWith({ViolationLevel? level}) {
    return ArchitectureViolation(
      ruleName: ruleName,
      packageName: packageName,
      dependencyName: dependencyName,
      reason: reason,
      level: level ?? this.level,
      category: category,
      subject: subject,
      isRisk: isRisk,
      findingCode: findingCode,
    );
  }

  FindingDefinition get definition {
    if (findingCode != null) return FindingRegistry.byCode(findingCode!);
    return FindingRegistry.forRule(ruleName);
  }

  String get code => definition.code;

  String get shortCode => definition.shortCode;

  FindingSeverity get effectiveSeverity {
    switch (level) {
      case ViolationLevel.error:
        return FindingSeverity.error;
      case ViolationLevel.warning:
        return FindingSeverity.warning;
      case ViolationLevel.observation:
        return FindingSeverity.observation;
    }
  }

  String get severityLabel {
    switch (effectiveSeverity) {
      case FindingSeverity.ok:
        return 'OK';
      case FindingSeverity.observation:
        return 'Observation';
      case FindingSeverity.warning:
        return 'Warning';
      case FindingSeverity.error:
        return 'Error';
    }
  }

  String get remediationAnchor => definition.docsAnchor;

  String remediationLink(String remediationPath) {
    return '$remediationPath#$remediationAnchor';
  }

  String get reportLine => '[$shortCode] [$category] $subject $reason';

  @override
  String toString() {
    if (level == ViolationLevel.observation) {
      return 'Architecture observation:\n'
          'subject: $subject\n'
          'reason: $reason';
    }
    if (level == ViolationLevel.warning) {
      return 'Architecture warning:\n'
          'subject: $subject\n'
          'reason: $reason';
    }
    return 'Architecture rule violation:\n'
        'rule: $ruleName\n'
        'package: $packageName\n'
        'depends on: $dependencyName\n'
        'reason: $reason';
  }
}
