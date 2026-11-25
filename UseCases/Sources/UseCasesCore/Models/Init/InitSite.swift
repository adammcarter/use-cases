/// What stands in the folder `init` is asked to set up (chapter 17 §3).
enum InitSite: Equatable {
  /// No workspace here, and none above.
  case fresh

  /// The folder is already the workspace root, with the prefix its `use-cases.yml` has.
  case workspace(prefix: Namespace?)
}
