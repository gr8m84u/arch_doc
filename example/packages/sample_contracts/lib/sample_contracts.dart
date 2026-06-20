import 'package:sample_core/sample_core.dart';

abstract class ReportRepository {
  Future<ArchitectureReport> load(ProjectId projectId);
}
