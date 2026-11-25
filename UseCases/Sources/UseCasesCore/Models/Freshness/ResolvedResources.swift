/// The files one route's resource declarations name, as a set (chapter 11 §44), and the
/// declarations that name nothing usable.
struct ResolvedResources: Equatable, Sendable {
  /// Each file once, however many declarations reached it.
  var files: Set<WorkspacePath> = []
  var problems: [ResourceProblem] = []
}
