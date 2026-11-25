/// Signs a use case off: records who approved its promise as it reads now, on which day, pinned
/// by the promise's fingerprint (chapter 02 `approved`, chapter 11 §89.9).
protocol ApprovalStamping: Sendable {
  /// The use case with its promise approved as it reads.
  ///
  /// A use case already approved as it reads keeps the approval it has: who signed it off and
  /// when stay as they were.
  ///
  /// - Parameters:
  ///   - definition: The use case, with the approval it has, if any.
  ///   - identifier: Its full id, which the fingerprint includes.
  ///   - approver: Who signs it off.
  ///   - day: Today, written `YYYY-MM-DD`.
  /// - Throws: ``ApprovalStampingError`` when the promise cannot be fingerprinted.
  func signed(
    _ definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    by approver: ApproverName,
    on day: String,
  ) throws(ApprovalStampingError) -> UseCaseDefinition
}
