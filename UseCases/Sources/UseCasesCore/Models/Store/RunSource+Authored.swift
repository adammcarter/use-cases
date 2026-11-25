extension RunSource {
  /// Reads one `sources` entry of a version 1 manifest.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var workingDirectory: WorkspacePath?
    if object.contains("working_dir") {
      workingDirectory = try object.requiredPath("working_dir")
    }

    var command: [String]?
    if object.contains("command") {
      command = try object.strings("command")
    }

    try self.init(
      identifier: object.requiredIdentifier(
        "id",
        parsing: IdentifierSegment.init(validating:),
      ),
      report: object.requiredString("report"),
      transformer: object.requiredString("transformer"),
      workingDirectory: workingDirectory,
      command: command,
      exitCode: object.optionalInteger("exit_code"),
      seconds: object.optionalNumber("seconds"),
      error: object.optionalString("error"),
      diagnostics: object.strings("diagnostics"),
    )
  }
}
