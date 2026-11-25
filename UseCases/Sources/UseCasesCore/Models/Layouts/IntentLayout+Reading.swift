extension IntentLayout {
  /// Reads the intent an agent sends: `what` and `why` in words, and optionally `who` as a list.
  init(authored input: AuthoredInput) throws(LayoutRenderingError) {
    let refusal = LayoutRenderingError.invalidIntent(name: input.name)

    guard
      let object = try? AuthoredObject(input.value, at: ""),
      Set(object.members.map(\.key)).isSubset(of: ["what", "why", "who"]),
      case let .string(what)? = object.value(for: "what"), !what.isWhitespaceOnly,
      case let .string(why)? = object.value(for: "why"), !why.isWhitespaceOnly
    else {
      throw refusal
    }

    var who: [String] = []

    if let written = object.value(for: "who") {
      guard case let .array(items) = written else {
        throw refusal
      }

      who = try items.map { item throws(LayoutRenderingError) in
        guard case let .string(person) = item, !person.isWhitespaceOnly else {
          throw refusal
        }

        return try Self.words(person, in: "who", of: input)
      }
    }

    try self.init(
      what: Self.words(what, in: "what", of: input),
      why: Self.words(why, in: "why", of: input),
      who: who,
    )
  }

  /// The text without the white space at its ends, refused when it holds a character a terminal
  /// would act on.
  private static func words(
    _ text: String,
    in field: String,
    of input: AuthoredInput,
  ) throws(LayoutRenderingError) -> String {
    if let character = text.firstTerminalControl {
      throw .controlCharacter(
        name: input.name,
        field: field,
        character: character,
      )
    }

    return text.withoutOuterWhitespace
  }
}
