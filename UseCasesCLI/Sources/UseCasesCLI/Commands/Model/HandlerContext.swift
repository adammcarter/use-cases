/// What a command handler is given: the normalized arguments, its parsed
/// flags, and whether JSON output was asked for.
struct HandlerContext: Sendable {
  let arguments: [String]
  let flags: ParsedFlags
  let isJSON: Bool
}
