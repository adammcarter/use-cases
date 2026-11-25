/// The words of a use case that `--like` finds others like, and the use case itself, which is
/// never a result.
struct LikeText: Equatable, Sendable {
  /// The words of its title, intent, scenarios and out of scope, each once, in the order met.
  let words: [String]

  /// Its id as written, when it has one.
  let identifier: String?

  /// Reads a use case as far as it goes. A draft is enough: what is missing, or is not text, is
  /// left alone.
  init(_ members: [AuthoredMember]) {
    var texts: [String] = []

    if case let .string(title)? = Self.value("title", in: members) {
      texts.append(title)
    }

    if case let .string(intent)? = Self.value("intent", in: members) {
      texts.append(intent)
    }

    if case let .array(scenarios)? = Self.value("scenarios", in: members) {
      for case let .object(scenario) in scenarios {
        for key in ["given", "when", "then"] {
          texts += Self.strings(Self.value(key, in: scenario))
        }
      }
    }

    texts += Self.strings(Self.value("out_of_scope", in: members))

    var seen: Set<String> = []

    words = texts.flatMap(\.searchWords).filter { word in
      seen.insert(word).inserted
    }

    if case let .string(identifier)? = Self.value("id", in: members) {
      self.identifier = identifier
    } else {
      identifier = nil
    }
  }

  private static func value(
    _ key: String,
    in members: [AuthoredMember],
  ) -> AuthoredValue? {
    members.first { member in
      member.key.isExactlyEqual(to: key)
    }?.value
  }

  private static func strings(_ value: AuthoredValue?) -> [String] {
    guard case let .array(items)? = value else {
      return []
    }

    return items.compactMap { item in
      guard case let .string(text) = item else {
        return nil
      }

      return text
    }
  }
}
