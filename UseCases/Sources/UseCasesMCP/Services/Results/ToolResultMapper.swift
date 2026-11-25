import MCP
import UseCasesCore

/// Gives the command's document back unchanged, as text and as structured content, and marks a
/// refusal as a tool error. Nothing is added, summarised or cut.
///
/// | The command printed | The result |
/// |---|---|
/// | a document with `error` | a tool error: the document as text, no structured content |
/// | a document, exit 0 or 1 | the document, as text exactly as printed and as structured content |
/// | a document with `cancelled`, exit 130 | the same: a verify run sealed as cancelled |
/// | any other document | a tool error: the document as text |
/// | no document | a tool error: what the command wrote to stderr |
struct ToolResultMapper: ToolResultMapping {
  private static let sealedCancellationExit: Int32 = 130

  private let reader: any JSONValueReading
  private let writer: any JSONValueWriting

  init(
    reader: any JSONValueReading = JSONValueReader(),
    writer: any JSONValueWriting = JSONValueWriter(),
  ) {
    self.reader = reader
    self.writer = writer
  }

  func result(
    for outcome: CommandOutcome,
    command: String,
  ) -> CallTool.Result {
    guard
      case let .object(members)? = reader.value(of: outcome.standardOutput)
    else {
      return failure(
        outcome,
        command: command,
      )
    }

    // Optional, so that the document is kept as it is and not encoded again.
    let document: Value? = .object(members)

    guard members["error"] == nil, isAnswer(outcome.ending, members: members) else {
      return CallTool.Result(
        content: [Self.text(outcome.standardOutput)],
        isError: true,
      )
    }

    return CallTool.Result(
      content: [Self.text(outcome.standardOutput)],
      structuredContent: document,
      isError: false,
    )
  }

  func refusal(_ document: ToolErrorDocument) -> CallTool.Result {
    CallTool.Result(
      content: [Self.text(writer.text(of: document.value) ?? document.message)],
      isError: true,
    )
  }

  /// Exit 0 and 1 are answers, and so is a sealed run that was cancelled.
  private func isAnswer(
    _ ending: CommandEnding,
    members: [String: Value],
  ) -> Bool {
    switch ending {
    case let .exited(code):
      code == 0 || code == 1
        || (code == Self.sealedCancellationExit && members["cancelled"] == .bool(true))
    case .signaled, .cancelled:
      false
    }
  }

  /// A command that printed no document said why on stderr, or ended in a way that says it.
  private func failure(
    _ outcome: CommandOutcome,
    command: String,
  ) -> CallTool.Result {
    CallTool.Result(
      content: [Self.text(Self.reason(of: outcome, command: command))],
      isError: true,
    )
  }

  private static func reason(
    of outcome: CommandOutcome,
    command: String,
  ) -> String {
    guard outcome.standardError.isEmpty else {
      return outcome.standardError
    }

    switch outcome.ending {
    case let .exited(code):
      return "use-cases \(command) ended with exit code \(code) and printed no document"
    case let .signaled(signal):
      return "use-cases \(command) was stopped by signal \(signal) and printed no document"
    case .cancelled:
      return "use-cases \(command) was cancelled"
    }
  }

  private static func text(_ text: String) -> Tool.Content {
    .text(
      text: text,
      annotations: nil,
      _meta: nil,
    )
  }
}
