/// The three lists a selector object may write (chapter 03), named as the file names them.
enum GroupSelectorKind: String, CaseIterable, Sendable {
  case ids
  case prefixes
  case globs
}
