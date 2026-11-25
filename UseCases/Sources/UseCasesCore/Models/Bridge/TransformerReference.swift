/// Which transformer a bridge entry names (chapter 10 §9).
enum TransformerReference: Equatable, Sendable {
  /// A transformer that ships with the build, by name.
  case bundled(String)

  /// A program in the project, by its path from the workspace root.
  case program(WorkspacePath)

  /// A name with a `/` in it is a project-relative program path; any other name is a bundled
  /// transformer's.
  init(text: String) throws(WorkspacePathError) {
    if text.unicodeScalars.contains("/") {
      self = try .program(WorkspacePath(validating: text))
    } else {
      self = .bundled(text)
    }
  }
}
