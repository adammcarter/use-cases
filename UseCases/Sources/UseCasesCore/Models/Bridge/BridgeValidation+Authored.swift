extension BridgeValidation {
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let run = try object.contains("run") ? object.strings("run") : nil

    try self.init(
      identifier: object.requiredIdentifier(
        "id",
        parsing: IdentifierSegment.init(validating:),
      ),
      report: object.optionalString("report"),
      run: run,
      workingDirectory: object.contains("working_dir") ? object.requiredPath("working_dir") : nil,
      transformer: object.requiredTransformer("transformer"),
      settings: object.value(for: "settings"),
      timeoutSeconds: object.optionalInteger("timeout_seconds"),
    )
  }
}
