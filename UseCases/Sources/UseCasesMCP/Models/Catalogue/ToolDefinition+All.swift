extension ToolDefinition {
  /// The thirteen tools of chapter 20 §3, in the order the chapter lists them. Never `init`,
  /// `hooks` or `record --interactive`: a person sets up a repository, and a terminal is not
  /// something a tool call has.
  static let all: [ToolDefinition] = [
    .validateFiles,
    .status,
    .verifyTests,
    .recordVerdict,
    .links,
    .search,
    .show,
    .save,
    .remove,
    .apply,
    .approve,
    .render,
    .docs,
  ]
}
