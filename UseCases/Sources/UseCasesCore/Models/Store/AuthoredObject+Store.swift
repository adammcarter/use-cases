/// Reading the shapes the store's files are made of, from a document that already passed its
/// schema (or, for a version this core does not read, only its envelope).
extension AuthoredObject {
  func requiredRunIdentifier(_ key: String) throws(AuthoredShapeError) -> RunIdentifier {
    let text = try requiredString(key)

    do {
      return try RunIdentifier(validating: text)
    } catch {
      throw .invalidValue(
        location: location(of: key),
        reason: error.description,
      )
    }
  }

  func requiredFingerprint(_ key: String) throws(AuthoredShapeError) -> RouteFingerprint {
    let text = try requiredString(key)

    do {
      return try RouteFingerprint(validating: text)
    } catch {
      throw .invalidValue(
        location: location(of: key),
        reason: error.description,
      )
    }
  }

  func optionalFingerprint(_ key: String) throws(AuthoredShapeError) -> RouteFingerprint? {
    guard contains(key) else {
      return nil
    }

    return try requiredFingerprint(key)
  }

  /// A whole number from zero up.
  func requiredCount(_ key: String) throws(AuthoredShapeError) -> Int {
    let count = try requiredInteger(key)

    guard count >= 0 else {
      throw .invalidValue(
        location: location(of: key),
        reason: "\(count) is below 0",
      )
    }

    return count
  }

  func optionalInteger(_ key: String) throws(AuthoredShapeError) -> Int? {
    guard contains(key) else {
      return nil
    }

    return try requiredInteger(key)
  }

  /// A number written with or without a fraction.
  func optionalNumber(_ key: String) throws(AuthoredShapeError) -> Double? {
    guard let value = value(for: key) else {
      return nil
    }
    guard let number = value.numericValue else {
      throw .wrongType(
        location: location(of: key),
        expected: "a number",
      )
    }

    return number
  }

  /// The members of the mapping under the key, each with the text it holds; an absent mapping
  /// has none.
  func textMembers(_ key: String) throws(AuthoredShapeError) -> [FileDigest] {
    guard let mapping = try optionalObject(key) else {
      return []
    }

    var digests: [FileDigest] = []
    for member in mapping.members {
      guard case let .string(text) = member.value else {
        throw .wrongType(
          location: mapping.location(of: member.key),
          expected: "text",
        )
      }
      digests.append(FileDigest(
        path: member.key,
        digest: text,
      ))
    }

    return digests
  }
}
