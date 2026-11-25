/// What looking up a path a bridge file names found: what stands there, or why it cannot be used.
enum PathLookup {
  case found(FileEntryKind)
  case problem(String)
}
