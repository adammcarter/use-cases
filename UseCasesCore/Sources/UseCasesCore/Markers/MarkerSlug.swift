/// A slug split into its row identifier and optional binding suffix.
public struct MarkerSlugParts: Equatable, Sendable {
  public let rowIdentifier: String
  public let suffix: String?

  /// `{ row_id, suffix }`, in the TypeScript's key order.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("suffix", suffix.map(JSONValue.string) ?? .null),
    ]))
  }
}

/// The slug grammar (spec 1.2 / 1.3):
///
///     slug           = row-id ["#" binding-suffix]
///     row-id         = ident {"." ident}
///     binding-suffix = suffix-ident {"." suffix-ident}
///     ident          = lower-alpha {lower-alpha | digit | "_"}
///     suffix-ident   = lower-alpha {lower-alpha | digit | "_" | "-"}
///
/// Scanned by hand rather than with `Regex`, which is not `Sendable`. The
/// grammar is ASCII, so nothing outside it can match.
public enum MarkerSlug {
  public static func isValid(_ slug: String) -> Bool {
    let units = Array(slug.utf16)
    var index = 0
    guard scanDottedIdentifiers(units, &index, allowsHyphen: false) else {
      return false
    }
    if index == units.count {
      return true
    }
    guard units[index] == CodeUnits.numberSign else {
      return false
    }
    index += 1
    return scanDottedIdentifiers(units, &index, allowsHyphen: true) && index == units.count
  }

  /// The row identifier and suffix of a valid slug; nil when it is not one.
  public static func split(_ slug: String) -> MarkerSlugParts? {
    guard isValid(slug) else {
      return nil
    }
    let units = Array(slug.utf16)
    guard let hash = units.firstIndex(of: CodeUnits.numberSign) else {
      return MarkerSlugParts(rowIdentifier: slug, suffix: nil)
    }
    return MarkerSlugParts(
      rowIdentifier: CodeUnits.string(units[..<hash]),
      suffix: CodeUnits.string(units[(hash + 1)...]),
    )
  }

  private static func scanDottedIdentifiers(
    _ units: [UInt16],
    _ index: inout Int,
    allowsHyphen: Bool,
  ) -> Bool {
    guard scanIdentifier(units, &index, allowsHyphen: allowsHyphen) else {
      return false
    }
    while index < units.count, units[index] == CodeUnits.fullStop {
      index += 1
      guard scanIdentifier(units, &index, allowsHyphen: allowsHyphen) else {
        return false
      }
    }
    return true
  }

  private static func scanIdentifier(
    _ units: [UInt16],
    _ index: inout Int,
    allowsHyphen: Bool,
  ) -> Bool {
    guard index < units.count, CodeUnits.isLowercaseASCIILetter(units[index]) else {
      return false
    }
    index += 1
    while index < units.count, isIdentifierContinuation(units[index], allowsHyphen: allowsHyphen) {
      index += 1
    }
    return true
  }

  private static func isIdentifierContinuation(
    _ unit: UInt16,
    allowsHyphen: Bool,
  ) -> Bool {
    CodeUnits.isLowercaseASCIILetter(unit)
      || CodeUnits.isASCIIDigit(unit)
      || unit == CodeUnits.lowLine
      || (allowsHyphen && unit == CodeUnits.hyphenMinus)
  }
}
