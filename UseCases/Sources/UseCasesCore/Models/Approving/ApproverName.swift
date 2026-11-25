import Foundation

/// The name a sign-off is recorded under (chapter 16 §14): who signed off, as the person
/// reviewing the commit will read it.
struct ApproverName: Equatable, Sendable {
  /// The most characters a name has, as the published schemas count them.
  static let longest = 200

  /// The name, without the space around it.
  let text: String

  /// Reads a name as typed after `--by` or `--approved-by`.
  ///
  /// - Throws: ``ApproverNameError`` when nothing is left once the space around it is taken
  ///   off, or more than ``longest`` characters are.
  init(validating typed: String) throws(ApproverNameError) {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      throw .blank
    }

    let count = trimmed.unicodeScalars.count

    guard count <= Self.longest else {
      throw .tooLong(count: count)
    }

    text = trimmed
  }
}
