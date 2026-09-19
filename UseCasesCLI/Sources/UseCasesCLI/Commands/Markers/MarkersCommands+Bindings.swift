extension MarkersCommands {
  static let bind = CommandSpecification(
    path: ["bind"],
    command: "markers.bind",
    summary: "Bind a use-case row to a code marker (inserts the marker into the source).",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      FlagSpecification(
        key: "row",
        name: "--row",
        kind: .string,
        summary: "Row id to bind.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "file",
        name: "--file",
        kind: .string,
        summary: "Source file to place the marker in.",
        valueName: "<path>",
      ),
      MarkersFlags.mode,
      MarkersFlags.startLine,
      MarkersFlags.endLine,
      FlagSpecification(
        key: "line",
        name: "--line",
        kind: .integer,
        summary: "Function line (REQUIRED for --mode swift-func).",
        valueName: "<n>",
      ),
      FlagSpecification(
        key: "suffix",
        name: "--suffix",
        kind: .string,
        summary: "Disambiguating suffix when a file binds more than one row.",
        valueName: "<s>",
      ),
      FlagSpecification(
        key: "registerExisting",
        name: "--register-existing",
        kind: .boolean,
        summary: "Register a marker already present in the source.",
      ),
      MarkersFlags.commentPrefix,
      FlagSpecification(
        key: "dryRun",
        name: "--dry-run",
        kind: .boolean,
        summary: "Preview the marker placement without writing the source or registry.",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runBind(context)
  }

  static let unbind = CommandSpecification(
    path: ["unbind"],
    command: "markers.unbind",
    summary: "Release a binding: remove its marker from the source and end its "
      + "registration.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      FlagSpecification(
        key: "row",
        name: "--row",
        kind: .string,
        summary: "Row id to release.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "suffix",
        name: "--suffix",
        kind: .string,
        summary: "Suffix of the binding to release (when a row has more than one).",
        valueName: "<s>",
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the binding ended (recorded on the release event; default `unbind`).",
        valueName: "<s>",
      ),
      FlagSpecification(
        key: "dryRun",
        name: "--dry-run",
        kind: .boolean,
        summary: "Report what would be released without writing the source or registry.",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runUnbind(context)
  }

  static let rebind = CommandSpecification(
    path: ["rebind"],
    command: "markers.rebind",
    summary: "Move a binding to a different declaration (marker and registration "
      + "together).",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      FlagSpecification(
        key: "row",
        name: "--row",
        kind: .string,
        summary: "Row id whose binding moves.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "file",
        name: "--file",
        kind: .string,
        summary: "Source file the marker moves TO (may differ from where it is now).",
        valueName: "<path>",
      ),
      MarkersFlags.mode,
      MarkersFlags.startLine,
      MarkersFlags.endLine,
      FlagSpecification(
        key: "line",
        name: "--line",
        kind: .integer,
        summary: "Function line (REQUIRED for --mode swift-func). Count lines as the "
          + "file will read once the OLD marker is gone.",
        valueName: "<n>",
      ),
      FlagSpecification(
        key: "suffix",
        name: "--suffix",
        kind: .string,
        summary: "Suffix of the binding to move (when a row has more than one).",
        valueName: "<s>",
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the binding moved (recorded on both events; default `rebind`).",
        valueName: "<s>",
      ),
      MarkersFlags.commentPrefix,
      FlagSpecification(
        key: "dryRun",
        name: "--dry-run",
        kind: .boolean,
        summary: "Preview the move without writing the source or registry.",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runRebind(context)
  }
}
