/// The problems loading reports itself, with their wording in one place.
extension Diagnostic {
  /// A definition file that could not be read.
  static func unreadableDefinition(
    _ file: WorkspacePath,
    because error: FileSystemError,
  ) -> Diagnostic {
    Diagnostic(
      error: "unreadable-definition",
      in: file,
      message: "the file cannot be read: \(error)",
    )
  }

  /// A full id that a second use case defines.
  static func duplicateUseCase(
    _ identifier: UseCaseIdentifier,
    in file: WorkspacePath,
    alsoIn first: WorkspacePath,
  ) -> Diagnostic {
    let place =
      file == first
        ? "more than once in this file"
        : "in '\(first)' as well"

    return Diagnostic(
      error: "duplicate-use-case",
      in: file,
      message: "use case '\(identifier)' is defined \(place); a full id names one use case",
    )
  }
}
