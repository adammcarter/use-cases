/// Types a plain scalar by YAML 1.2's core schema, and finds the ones YAML 1.1 would type
/// differently (chapter 09 §14).
struct PlainScalarTyper: PlainScalarTyping {
  private let yaml12: any YAMLSchemaResolving
  private let yaml11: any YAMLSchemaResolving

  init(
    yaml12: any YAMLSchemaResolving = YAML12CoreSchema(),
    yaml11: any YAMLSchemaResolving = YAML11Schema(),
  ) {
    self.yaml12 = yaml12
    self.yaml11 = yaml11
  }

  func type(of text: String) -> PlainScalarTyped {
    let core = yaml12.resolve(text)

    if core == .integer(.tooLarge) {
      return .integerTooLarge
    }

    if case let .number(value) = core, !value.isFinite {
      return .notJSONNumber
    }

    let legacy = yaml11.resolve(text)

    guard core.agrees(with: legacy) else {
      return .readDifferently(
        yaml11: legacy,
        yaml12: core,
      )
    }

    return .value(authoredValue(of: core, text: text))
  }

  private func authoredValue(
    of resolved: YAMLResolvedScalar,
    text: String,
  ) -> AuthoredValue {
    switch resolved {
    case .null: .null
    case let .boolean(value): .boolean(value)
    case let .integer(.exact(value)): .integer(value)
    case let .number(value): .number(value)
    default: .string(text)
    }
  }
}
