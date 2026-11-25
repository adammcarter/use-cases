/// One resolved resource file and its content (chapter 11 §41, §89.6). Globs are already
/// expanded and files deduplicated by workspace path.
struct ResourceContribution: Equatable, Sendable {
  let file: WorkspacePath
  let content: ContentReference
}
