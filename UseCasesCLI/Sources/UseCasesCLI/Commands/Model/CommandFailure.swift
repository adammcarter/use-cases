import UseCasesCore

/// A failure a handler throws instead of returning an envelope. The dispatcher
/// renders it as the standard error envelope with exit 1, as the TypeScript
/// renders any thrown error: its `code` when it carries one, else
/// `internal_error`.
struct CommandFailure: Error, Sendable, Equatable {
  static let internalErrorCode = "internal_error"

  let code: String
  let message: String

  init(
    code: String,
    message: String,
  ) {
    self.code = code
    self.message = message
  }

  init(_ error: WorkspaceError) {
    self.init(code: error.code, message: error.message)
  }

  init(_ error: SchemaError) {
    self.init(code: error.code, message: error.message)
  }

  init(_ error: FileAccessError) {
    self.init(code: error.code, message: error.message)
  }

  init(_ error: SkillAssetValidationError) {
    self.init(code: error.code ?? Self.internalErrorCode, message: error.message)
  }
}
