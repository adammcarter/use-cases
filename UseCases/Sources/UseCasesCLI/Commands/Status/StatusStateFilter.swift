import Foundation
import UseCasesCore

/// The states `--state` asks for (chapter 16 §9): `failed,stale`, where `draft` is a state too.
struct StatusStateFilter: Equatable {
  /// The states, never empty.
  let states: Set<VerificationStatus>

  /// Reads the comma-separated words of `--state`.
  ///
  /// - Throws: ``StatusStateFilterError`` for a word that is no state, or for no word at all.
  init(parsing text: String) throws(StatusStateFilterError) {
    let words = text.split(
      separator: ",",
      omittingEmptySubsequences: false,
    ).map(String.init)

    var states: Set<VerificationStatus> = []
    var unknown: [String] = []

    for untrimmed in words {
      let word = untrimmed.trimmingCharacters(in: .whitespaces)

      if let state = VerificationStatus(rawValue: word) {
        states.insert(state)
      } else {
        unknown.append(word)
      }
    }

    guard unknown.isEmpty else {
      throw .unknown(unknown)
    }

    self.states = states
  }

  func contains(_ state: VerificationStatus) -> Bool {
    states.contains(state)
  }
}
