/// What loading the groups file found: the resolved groups when the file is there and is valid,
/// and every problem and warning otherwise.
struct GroupsLoadResult: Equatable, Sendable {
  /// Empty when there is no groups file, and when it has a problem.
  let groups: [UseCaseGroup]
  let diagnostics: [Diagnostic]
}
