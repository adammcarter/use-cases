/// Reads one key of a proposal file at a time, refusing a value of the wrong shape in words that
/// name the key.
struct ProposalKeys {
  let object: AuthoredObject
  let name: String

  func title() throws(LayoutRenderingError) -> String {
    guard case let .string(text)? = object.value(for: "title"), !text.isWhitespaceOnly else {
      throw refusal("a proposal has a `title`: the change in a few words")
    }

    return try words(text, in: "title")
  }

  func untouched() throws(LayoutRenderingError) -> [String] {
    guard let value = object.value(for: "untouched") else {
      return []
    }

    guard case let .array(items) = value else {
      throw refusal("`untouched` lists the full ids of use cases checked and left alone")
    }

    return try items.map { item throws(LayoutRenderingError) in
      guard case let .string(identifier) = item else {
        throw refusal("`untouched` lists the full ids of use cases checked and left alone")
      }

      return identifier
    }
  }

  /// The ids `untouched` lists, each once.
  func untouchedOnce() throws(LayoutRenderingError) -> [String] {
    let identifiers = try untouched()
    var seen: Set<[UInt8]> = []

    for identifier in identifiers where !seen.insert(Array(identifier.utf8)).inserted {
      throw refusal("`untouched` lists '\(identifier.displayEscaped)' more than once")
    }

    return identifiers
  }

  func fits() throws(LayoutRenderingError) -> [String: ProposalFit] {
    var fits: [String: ProposalFit] = [:]

    for (identifier, value) in try members(
      "fits",
      meaning: "`fits` maps a use case's full id to extends or changes",
    ) {
      guard case let .string(word) = value, let fit = ProposalFit(rawValue: word),
            fit == .extends || fit == .changes
      else {
        throw refusal(
          "`fits` can say extends or changes for \(identifier.displayEscaped); "
            + "the rest follow from the batch",
        )
      }

      fits[identifier] = fit
    }

    return fits
  }

  func youSee() throws(LayoutRenderingError) -> [String: String] {
    var seen: [String: String] = [:]

    for (identifier, value) in try members(
      "you_see",
      meaning: "`you_see` maps a use case's full id to what the person will see",
    ) {
      guard case let .string(text) = value, !text.isWhitespaceOnly else {
        throw refusal(
          "`you_see` for \(identifier.displayEscaped) says what the person will see, in words",
        )
      }

      seen[identifier] = try words(text, in: "you_see for \(identifier.displayEscaped)")
    }

    return seen
  }

  func decisions() throws(LayoutRenderingError) -> [ProposalDecision] {
    guard let value = object.value(for: "decisions") else {
      return []
    }

    guard case let .array(items) = value else {
      throw refusal("`decisions` is a list of choices for the person")
    }

    return try items.map { item throws(LayoutRenderingError) in
      try decision(item)
    }
  }

  func golden() throws(LayoutRenderingError) -> [String: [String]] {
    var golden: [String: [String]] = [:]

    for (identifier, value) in try members(
      "golden",
      meaning: "`golden` maps a use case's full id to the ids of its golden scenarios",
    ) {
      guard case let .array(items) = value else {
        throw refusal(
          "`golden` for \(identifier.displayEscaped) lists the ids of its golden scenarios",
        )
      }

      golden[identifier] = try items.map { item throws(LayoutRenderingError) in
        guard case let .string(scenario) = item else {
          throw refusal(
            "`golden` for \(identifier.displayEscaped) lists the ids of its golden scenarios",
          )
        }

        return scenario
      }
    }

    return golden
  }

  private func decision(_ value: AuthoredValue) throws(LayoutRenderingError) -> ProposalDecision {
    let meaning = "a decision has a `question` and at least two `options` (text), and nothing else"

    guard case let .object(members) = value,
          Set(members.map(\.key)) == ["question", "options"],
          case let .string(question)? = value.member("question"), !question.isWhitespaceOnly,
          case let .array(items)? = value.member("options"), items.count >= 2
    else {
      throw refusal(meaning)
    }

    let options = try items.map { item throws(LayoutRenderingError) in
      guard case let .string(option) = item, !option.isWhitespaceOnly else {
        throw refusal(meaning)
      }

      return try words(option, in: "decisions options")
    }

    return try ProposalDecision(
      question: words(question, in: "decisions question"),
      options: options,
    )
  }

  private func members(
    _ key: String,
    meaning: String,
  ) throws(LayoutRenderingError) -> [(String, AuthoredValue)] {
    guard let value = object.value(for: key) else {
      return []
    }

    guard case let .object(members) = value else {
      throw refusal(meaning)
    }

    return members.map { member in
      (member.key, member.value)
    }
  }

  /// The text without the white space at its ends, refused when it holds a character a terminal
  /// would act on.
  private func words(
    _ text: String,
    in field: String,
  ) throws(LayoutRenderingError) -> String {
    if let character = text.firstTerminalControl {
      throw .controlCharacter(
        name: name,
        field: field,
        character: character,
      )
    }

    return text.withoutOuterWhitespace
  }

  private func refusal(_ problem: String) -> LayoutRenderingError {
    .invalidProposal(
      name: name,
      problem: problem,
    )
  }
}

private extension AuthoredValue {
  func member(_ key: String) -> AuthoredValue? {
    guard case let .object(members) = self else {
      return nil
    }

    return members.first { member in
      member.key == key
    }?.value
  }
}
