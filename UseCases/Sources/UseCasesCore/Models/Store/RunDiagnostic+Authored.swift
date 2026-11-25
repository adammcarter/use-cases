extension RunDiagnostic {
  /// Reads one `diagnostics` entry of a version 1 manifest.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var useCase: UseCaseIdentifier?
    if object.contains("use_case") {
      useCase = try object.requiredIdentifier(
        "use_case",
        parsing: UseCaseIdentifier.init(validating:),
      )
    }

    var route: RouteIdentifier?
    if object.contains("route") {
      route = try object.requiredIdentifier(
        "route",
        parsing: RouteIdentifier.init(validating:),
      )
    }

    var files: [WorkspacePath] = []
    for (index, text) in try object.strings("files").enumerated() {
      do {
        try files.append(WorkspacePath(validating: text))
      } catch {
        throw .invalidPath(
          location: "files[\(index)]",
          error,
        )
      }
    }

    try self.init(
      problem: object.requiredString("problem"),
      useCase: useCase,
      route: route,
      fingerprint: object.optionalFingerprint("fingerprint"),
      files: files,
      links: object.strings("links"),
    )
  }
}
