extension ToolArgument {
  /// Every tool but `docs` takes it.
  static let workspace = ToolArgument(
    name: "workspace",
    type: .string,
    placement: .workspace,
    description: """
    The workspace root folder, instead of finding it from the folder the server started in.
    """,
  )

  static let dryRun = ToolArgument(
    name: "dry_run",
    type: .boolean,
    placement: .flag("--dry-run"),
    description: """
    Check the change and report what it would do, writing nothing. The preview is exactly what \
    the same call without it writes.
    """,
  )

  static let pageSize = ToolArgument(
    name: "page_size",
    type: .integer,
    placement: .option("--page-size"),
    description: "Matches in a page, 1 to 100. The default is 20.",
    range: 1 ... 100,
  )

  static let next = ToolArgument(
    name: "next",
    type: .string,
    placement: .option("--next"),
    description: """
    The `next` token of an earlier page, to get the page after it. Passed alone: it carries the \
    whole search.
    """,
  )

  static let exact = ToolArgument(
    name: "exact",
    type: .boolean,
    placement: .flag("--exact"),
    description: "Match only whole words, exactly as written: no word starts, no typos.",
  )
}

extension ToolArgument {
  /// The states of a use case a filter takes, as `status` shows them; `draft` is one here.
  static let states = [
    "failed", "error", "incomplete", "unverified", "stale", "verified", "draft",
  ]
}
