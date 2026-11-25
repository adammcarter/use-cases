/// A command of chapter 16 §2, built or not: the design names them all, so that the help lists
/// every one and a command not built yet is told apart from one that does not exist.
enum DesignedCommand: String, CaseIterable {
  case validate
  case status
  case verify
  case record
  case links
  case search
  case show
  case save
  case remove
  case apply
  case approve
  case `init`
  case hooks
  case prune
  case render
  case docs
  case mcp

  /// Whether this build answers the command (`docs/architecture.md` §6).
  var isBuilt: Bool {
    switch self {
    case .validate, .status, .verify, .record, .links, .search, .`init`, .hooks, .show, .save,
         .remove, .apply, .approve, .render, .docs, .prune, .mcp:
      true
    }
  }
}
