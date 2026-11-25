extension ResultOrigin {
  /// Reads `via` and, for a verdict that did not come from `record`, `links`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let via = try object.strings("via")

    guard via != [Self.recordName] else {
      self = .recorded
      return
    }

    var identifiers: [IdentifierSegment] = []
    for (index, text) in via.enumerated() {
      do {
        try identifiers.append(IdentifierSegment(validating: text))
      } catch {
        throw .invalidIdentifier(
          location: "via[\(index)]",
          error,
        )
      }
    }

    var links: [LinkResult] = []
    if let mapping = try object.optionalObject("links") {
      for member in mapping.members {
        try links.append(LinkResult(
          key: member.key,
          verdict: Self.verdict(
            of: member.value,
            at: mapping.location(of: member.key),
          ),
        ))
      }
    }

    self = .validations(
      identifiers,
      links: links,
    )
  }

  /// What `via` holds for a verdict that was recorded by hand.
  static let recordName = "record"

  private static func verdict(
    of value: AuthoredValue,
    at location: String,
  ) throws(AuthoredShapeError) -> Verdict? {
    switch value {
    case .null:
      return nil
    case let .string(text):
      if let verdict = Verdict(rawValue: text) {
        return verdict
      }

      throw .unknownChoice(
        location: location,
        text: text,
      )
    default:
      throw .wrongType(
        location: location,
        expected: "a verdict or null",
      )
    }
  }
}
