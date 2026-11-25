extension StoredResult {
  /// The result as a line of `results.jsonl` writes it (chapter 12 §12), or `nil` for a result
  /// of a newer version, which has only its envelope and so cannot be written.
  var document: StoreJSONValue? {
    guard let detail else {
      return nil
    }

    let via: [String]
    var links: StoreJSONValue?

    switch detail.origin {
    case .recorded:
      via = [ResultOrigin.recordName]
    case let .validations(identifiers, linkResults):
      via = identifiers.map(\.text)
      links = .object(
        linkResults.map { link in
          StoreJSONMember(
            key: link.key,
            value: link.verdict.map(\.rawValue).map(StoreJSONValue.string) ?? .null,
          )
        },
      )
    }

    return .present([
      "record_version": .integer(1),
      "use_case": .string(useCase.text),
      "route": .string(route.text),
      "fingerprint": .string(fingerprint.text),
      "status": .string(verdict.rawValue),
      "links": links,
      "via": .strings(via),
      "recorded_at": .string(detail.recordedAt),
      "message": detail.message.map(StoreJSONValue.string),
      "attachments": detail.attachments.isEmpty
        ? nil
        : .array(detail.attachments.map(\.document)),
    ])
  }
}
