/// Whether a `use-cases.yml` is the workspace root's or a child scope's (chapter 04). The loader
/// knows it from where the file sits; the file itself only says `root: true` at the root.
enum ScopeRole: Equatable, Sendable {
  case root
  case child
}
