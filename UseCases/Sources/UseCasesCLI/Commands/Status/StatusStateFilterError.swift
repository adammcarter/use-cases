import UseCasesCore

/// Why `--state` could not be read.
enum StatusStateFilterError: Error, Equatable {
  /// These words are no state. An empty word, as in `failed,`, is among them.
  case unknown([String])

  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case let .unknown(words):
      "--state: unknown: \(words.map(Self.named).joined(separator: ", ")); "
        + "the states are \(VerificationStatus.allCases.map(\.rawValue).joined(separator: ", "))"
    }
  }

  /// A word as the refusal names it: an empty one, as in `failed,`, is said in words.
  private static func named(_ word: String) -> String {
    word.isEmpty ? "an empty state" : word
  }
}
