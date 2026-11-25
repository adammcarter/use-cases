/// Whether a use case's promise is signed off as it reads now (chapter 21).
public enum ApprovalState: String, Sendable {
  /// Signed off, and the promise has not changed since.
  case approved

  /// Signed off, and then the promise changed.
  case changed

  /// Never signed off.
  case unapproved

  /// The state of a use case that has this approval, whose promise fingerprints to `promise`.
  init(
    approval: Approval?,
    promise: String,
  ) {
    guard let approval else {
      self = .unapproved
      return
    }

    self = approval.behaviour.isExactlyEqual(to: promise) ? .approved : .changed
  }
}
