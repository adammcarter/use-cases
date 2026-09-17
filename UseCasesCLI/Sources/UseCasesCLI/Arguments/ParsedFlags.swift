/// A command's flags, parsed, by key.
struct ParsedFlags: Sendable, Equatable {
  private var values: [String: ParsedFlagValue] = [:]

  subscript(key: String) -> ParsedFlagValue? {
    get {
      values[key]
    }
    set {
      values[key] = newValue
    }
  }
}
