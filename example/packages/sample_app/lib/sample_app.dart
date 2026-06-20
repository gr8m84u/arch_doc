import 'package:sample_contracts/sample_contracts.dart';
import 'package:sample_core/sample_core.dart';

class InMemoryReports implements ReportRepository {
  @override
  Future<ArchitectureReport> load(ProjectId projectId) async {
    return ArchitectureReport(
      projectId: projectId,
      summary: 'Example architecture report',
    );
  }
}

class ReportViewer {
  final ReportRepository repository;

  const ReportViewer(this.repository);

  Future<String> titleFor(ProjectId projectId) async {
    final report = await repository.load(projectId);
    return report.summary;
  }
}
