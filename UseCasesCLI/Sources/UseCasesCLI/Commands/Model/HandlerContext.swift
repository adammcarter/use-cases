import UseCasesCore

/// What a command handler is given: the normalized arguments, its parsed
/// flags, whether JSON output was asked for, the environment — what the
/// TypeScript reads as `process.env`, and what child processes run with — and
/// the stderr the command writes on its way (a child's inherited stderr, or
/// `scan --ci`'s inferred spans), kept even when the handler then throws.
struct HandlerContext: Sendable {
  let arguments: [String]
  let flags: ParsedFlags
  let isJSON: Bool
  let environment: [String: String]
  let standardError: ProcessStandardErrorLog
}
