/// Writes a sign-off as the lines of the `approved` field of a use case.
protocol ApprovalSerialising: Sendable {
  /// The lines of an `approved` field alone, as it is written in a use case: its key and what it
  /// holds, the key `indent` spaces in.
  func lines(
    of approval: Approval,
    indent: Int,
  ) -> [String]
}
