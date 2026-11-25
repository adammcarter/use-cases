/// One test from a tool's report, with the place in the source where it is declared.
struct LocatedTest: Equatable, Sendable {
  let test: String
  /// Workspace-relative path; nil when the test could not be placed.
  let file: String?
  let line: Int?
  let status: ResultStatus
}
