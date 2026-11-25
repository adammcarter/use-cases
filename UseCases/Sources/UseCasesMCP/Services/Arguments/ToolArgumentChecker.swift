import MCP
import UseCasesCore

/// Checks the arguments of a call against the schema the host was shown, with the core's own
/// schema checker, and words what is wrong the way the tools do: `needs step`, `takes no shell`.
struct ToolArgumentChecker: ToolArgumentChecking {
  private let validator: any JSONSchemaValidating
  private let writer: any JSONValueWriting

  /// - Parameters:
  ///   - schema: The tool's input schema.
  ///   - writer: Writes the arguments for the checker.
  init(
    schema: Value,
    writer: any JSONValueWriting = JSONValueWriter(),
  ) throws(ToolArgumentCheckerError) {
    guard let schemaText = writer.text(of: schema) else {
      throw .unwritable
    }

    do {
      validator = try JSONSchemaValidator(schemaText: schemaText)
    } catch {
      throw .unusable(reason: "\(error)")
    }

    self.writer = writer
  }

  func refusal(of arguments: [String: Value]) -> String? {
    guard let text = writer.text(of: .object(arguments)) else {
      return "the arguments cannot be written as JSON"
    }

    let sentences = validator.problems(in: text).compactMap { problem in
      Self.sentence(of: problem)
    }

    return sentences.isEmpty ? nil : sentences.joined(separator: "; ")
  }

  /// The schema keywords whose breaks the command line words itself.
  private static let refusedByTheCommand: Set<String> = ["enum", "minimum", "maximum"]

  private static func sentence(of problem: JSONSchemaProblem) -> String? {
    switch problem {
    case let .unreadable(reason):
      "the arguments are not JSON: \(reason)"
    case let .missing(path, member):
      "needs \(located(member, in: path))"
    case let .unexpected(path, members):
      "takes no \(members.map { located($0, in: path) }.joined(separator: ", "))"
    case let .breaks(path, keyword, message):
      // The values and the range a description names are the command line's to refuse.
      Self.refusedByTheCommand.contains(keyword)
        ? nil : "\(path.isEmpty ? "the arguments" : path): \(message)"
    }
  }

  private static func located(
    _ member: String,
    in path: String,
  ) -> String {
    path.isEmpty ? member : "\(path)/\(member)"
  }
}
