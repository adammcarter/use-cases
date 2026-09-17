/// One parsed flag value. An absent flag has no value at all, as the
/// TypeScript leaves it `undefined`.
enum ParsedFlagValue: Sendable, Equatable {
  case boolean(Bool)
  case string(String)
  case strings([String])
  case number(Double)
}
