import UseCasesCore

/// A failure a tool handler throws instead of returning an envelope.
///
/// `callMcpTool` catches it and renders the standard error envelope under the
/// tool's CLI command name, as the TypeScript renders any thrown error: its
/// `code` when it carries one, else `internal_error`.
public struct McpToolFailure: Error, Sendable, Equatable {
  public static let internalErrorCode = "internal_error"

  public let code: String
  public let message: String

  public init(
    code: String,
    message: String,
  ) {
    self.code = code
    self.message = message
  }

  public init(_ error: WorkspaceError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: SchemaError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: FileAccessError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: UseCaseMatrixError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: EvidenceEventError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: ShowcaseError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: PresentationError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: DemoCapsuleError) {
    self.init(code: error.code, message: error.message)
  }

  public init(_ error: MarkerCommandError) {
    self.init(code: error.code, message: error.message)
  }
}
