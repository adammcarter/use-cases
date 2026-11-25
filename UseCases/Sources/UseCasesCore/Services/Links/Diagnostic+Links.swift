/// The problems the scan of the code reports, with their wording in one place (chapter 08,
/// chapter 09 §20.3).
extension Diagnostic {
  /// A well-paired marker for a use case that does not exist: no link.
  static func markerForUnknownUseCase(_ placed: FileRegion) -> Diagnostic {
    let target = placed.region.target

    return located(
      placed.file,
      line: placed.region.startLine,
      code: .markerUnknownUseCase,
      severity: .warning,
      message: "marker for unknown use case: '\(target)' names '\(target.useCase)', which is "
        + "not a use case of this workspace, so it links nothing",
    )
  }

  /// A well-paired marker for a route its use case does not have: no link.
  static func markerForUnknownRoute(_ placed: FileRegion) -> Diagnostic {
    let target = placed.region.target
    let route = target.route?.text ?? ""

    return located(
      placed.file,
      line: placed.region.startLine,
      code: .markerUnknownRoute,
      severity: .warning,
      message: "marker for unknown route: '\(target)' names route '\(route)', which use case "
        + "'\(target.useCase)' does not have, so it links nothing",
    )
  }

  /// A file the scan cannot read: the links in it are unknown.
  static func unreadableFile(
    _ file: WorkspacePath,
    because error: FileSystemError,
  ) -> Diagnostic {
    Diagnostic(
      error: .unreadableFile,
      in: file,
      message: "the file cannot be read, so the links in it are unknown: \(error)",
    )
  }

  /// A pipe, socket or device: skipped, and never opened.
  static func specialFileSkipped(_ file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      file: file,
      position: nil,
      code: .specialFileSkipped,
      severity: .warning,
      message: "it is a pipe, socket or device, so it is skipped and was never opened",
    )
  }

  /// A file whose name no workspace path can spell: skipped.
  static func unspellableFile(
    _ name: String,
    in folder: WorkspacePath,
    because error: WorkspacePathError,
  ) -> Diagnostic {
    Diagnostic(
      file: folder,
      position: nil,
      code: .unscannableName,
      severity: .warning,
      message: "\(name) is skipped, so its markers are not read: \(error.reason)",
    )
  }

  /// A diagnostic at a line of a file.
  static func located(
    _ file: WorkspacePath,
    line: Int,
    code: DiagnosticCode,
    severity: DiagnosticSeverity,
    message: String,
  ) -> Diagnostic {
    Diagnostic(
      file: file,
      position: try? SourcePosition(line: line),
      code: code,
      severity: severity,
      message: message,
    )
  }
}
