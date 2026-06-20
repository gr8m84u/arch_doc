class ProjectId {
  final String value;

  const ProjectId(this.value);
}

class ArchitectureReport {
  final ProjectId projectId;
  final String summary;

  const ArchitectureReport({required this.projectId, required this.summary});
}
