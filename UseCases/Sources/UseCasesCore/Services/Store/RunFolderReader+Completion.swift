extension RunFolderReader {
  /// Reads `completion.json`. A marker of version 1 is checked against the completion schema; a
  /// newer one is read through the four members every version keeps.
  func readCompletion(
    _ file: StoreFile,
    of identifier: RunIdentifier,
  ) throws(StoreProblem) -> RunCompletion {
    let bytes = try access.requiredBytes(of: file)
    let value = try access.document(
      bytes,
      in: file,
    )
    let object = try objectDocument(
      value,
      in: file,
    )

    let completion: RunCompletion
    if isNewer(value, versionKey: "completion_version") {
      completion = try decode(file) { () throws(AuthoredShapeError) in
        try RunCompletion(envelopeOf: object)
      }
      try requireDigests(
        of: completion,
        in: file,
      )
    } else {
      try requireValid(
        value,
        against: checks.completion,
        in: file,
      )
      completion = try decode(file) { () throws(AuthoredShapeError) in
        try RunCompletion(authored: object)
      }
    }

    guard completion.identifier == identifier else {
      throw .corrupt(
        file.location,
        "its run_id \(completion.identifier) is not the folder's, \(identifier)",
      )
    }

    return completion
  }

  /// Reads a document that passed its schema, or its envelope, into a model. A value the model
  /// cannot take is corruption.
  func decode<Value>(
    _ file: StoreFile,
    _ read: () throws(AuthoredShapeError) -> Value,
  ) throws(StoreProblem) -> Value {
    do {
      return try read()
    } catch {
      throw .corrupt(file.location, error.description)
    }
  }

  /// Reads a document as a JSON object.
  func objectDocument(
    _ value: AuthoredValue,
    in file: StoreFile,
  ) throws(StoreProblem) -> AuthoredObject {
    do {
      return try AuthoredObject(
        value,
        at: "",
      )
    } catch {
      throw .corrupt(file.location, "it is not a JSON object")
    }
  }

  /// Whether the document writes an integer version above the one this core reads.
  func isNewer(
    _ value: AuthoredValue,
    versionKey: String,
  ) -> Bool {
    guard
      case let .object(members) = value,
      case let .integer(version)? = members.first(where: { $0.key == versionKey })?.value
    else {
      return false
    }

    return version > Self.supportedVersion
  }

  /// Refuses a document that breaks its schema, naming the first problems.
  func requireValid(
    _ value: AuthoredValue,
    against checker: any SchemaChecking,
    in file: StoreFile,
    context: String = "",
  ) throws(StoreProblem) {
    let failures = checker.check(value)

    guard failures.isEmpty else {
      let summary = failures.prefix(3).map(\.description).joined(separator: "; ")

      throw .corrupt(file.location, context + summary)
    }
  }

  private func requireDigests(
    of completion: RunCompletion,
    in file: StoreFile,
  ) throws(StoreProblem) {
    guard completion.version >= Self.supportedVersion else {
      throw .corrupt(file.location, "completion_version \(completion.version) is below 1")
    }

    for (name, digest) in [
      ("manifest_sha256", completion.manifestDigest),
      ("results_sha256", completion.resultsDigest),
    ] where !Self.isSHA256(digest) {
      throw .corrupt(file.location, "\(name) is not a SHA-256 digest")
    }
  }

  static func isSHA256(_ text: String) -> Bool {
    text.unicodeScalars.count == 64 && text.unicodeScalars.allSatisfy {
      ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x66)
    }
  }
}
