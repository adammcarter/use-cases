/// The proposal file (chapter 21 §7, ADR 033): the batch `apply` takes, and what only the
/// conversation knows. `apply` ignores the second part, so the file the person signed off is the
/// file applied.
struct ProposalFile: Equatable, Sendable {
  /// What the input is called in a message: `stdin`, or the path as typed.
  let name: String

  /// The change in a few words.
  let title: String

  /// The removals and saves.
  let batch: UseCaseBatch

  /// The full ids checked and left alone.
  let untouched: [String]

  /// `extends` or `changes`, for a save that changes an existing use case.
  let fits: [String: ProposalFit]

  /// What the person will see, by use case.
  let youSee: [String: String]

  let decisions: [ProposalDecision]

  /// The scenarios that are a use case's golden path, by use case.
  let golden: [String: [String]]
}

extension ProposalFile {
  /// Whether the batch removes or saves the use case.
  func names(_ identifier: String) -> Bool {
    batch.removals.contains { removed in
      removed.isExactlyEqual(to: identifier)
    } || batch.saves.contains { save in
      save.identifier.text.isExactlyEqual(to: identifier)
    }
  }
}
