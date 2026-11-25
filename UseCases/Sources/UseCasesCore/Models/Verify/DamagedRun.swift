/// An unsealed verify run whose own files are damaged (chapter 13 §6): it is refused by name,
/// never skipped.
struct DamagedRun: Equatable, Sendable {
  let identifier: RunIdentifier

  /// The file that is wrong, and how.
  let problem: StoreProblem

  /// Whether `verify --abort --run-id` can still seal the run: its manifest reads and it has a
  /// start stamp to seal, even if the stamp itself cannot be read (the seal only digests it).
  let canBeClosed: Bool

  /// What a refusal says: the file, and how the run can be closed when it can.
  var message: String {
    guard canBeClosed else {
      return "\(problem); run \(identifier.text) cannot be closed by `use-cases verify --abort` "
        + "either, because a verify run is sealed with its start stamp"
    }

    return "\(problem); `use-cases verify --abort --run-id \(identifier.text)` closes the run"
  }
}
