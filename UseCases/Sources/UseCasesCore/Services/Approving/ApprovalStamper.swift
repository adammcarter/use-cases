/// Signs a use case off with the fingerprint of its promise that status reads approval by.
struct ApprovalStamper: ApprovalStamping {
  private let fingerprinter: any PromiseFingerprinting

  init(fingerprinter: any PromiseFingerprinting = PromiseFingerprinter()) {
    self.fingerprinter = fingerprinter
  }

  func signed(
    _ definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    by approver: ApproverName,
    on day: String,
  ) throws(ApprovalStampingError) -> UseCaseDefinition {
    let promise: String

    do {
      promise = try fingerprinter.fingerprint(
        of: PromiseFingerprintInput(
          definition: definition,
          identifier: identifier,
        ),
      )
    } catch {
      throw .unfingerprintable(
        identifier: identifier.text,
        reason: "\(error)",
      )
    }

    guard ApprovalState(approval: definition.approval, promise: promise) != .approved else {
      return definition
    }

    return definition.approved(
      Approval(
        approver: approver.text,
        day: day,
        behaviour: promise,
      ),
    )
  }
}
