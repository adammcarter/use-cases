/// The id of a validation in the bridge settings (chapters 05 and 10): a segment, and never a
/// name the bridge keeps for itself.
///
/// `record` names recorded verdicts. The names Windows reserves for devices are refused too,
/// because the id is also the name of a folder in every run.
struct ValidationIdentifier: Hashable, Sendable, CustomStringConvertible {
  private static let reservedNames: Set<String> = [
    "record", "con", "prn", "aux", "nul",
    "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
    "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
  ]

  let segment: IdentifierSegment

  /// Reads the id, refusing anything off the segment grammar and the reserved names.
  init(validating text: String) throws(IdentityError) {
    let parsed = try IdentifierSegment(validating: text)

    guard !Self.reservedNames.contains(parsed.text) else {
      throw .reserved(text)
    }

    segment = parsed
  }

  var text: String {
    segment.text
  }

  var description: String {
    text
  }
}
