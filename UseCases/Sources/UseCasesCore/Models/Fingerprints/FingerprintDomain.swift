/// The kind of thing a fingerprint identifies (chapter 11 §6). Each has its own hash domain, so a
/// digest of one kind is never mistaken for another.
enum FingerprintDomain: CaseIterable, Sendable {
  case content
  case route
  case workspace
  case promise

  /// The text hashed in front of the payload (§89.2).
  var name: String {
    switch self {
    case .content: "use-cases/content/v1"
    case .route: "use-cases/route/v1"
    case .workspace: "use-cases/workspace/v1"
    case .promise: "use-cases/promise/v1"
    }
  }

  /// What is written before the digest where the fingerprint is shown or stored (§4). A promise
  /// fingerprint is the bare digest.
  var externalPrefix: String? {
    switch self {
    case .content: "uc-content-v1-sha256:"
    case .route: "uc-route-v1-sha256:"
    case .workspace: "uc-workspace-v1-sha256:"
    case .promise: nil
    }
  }
}
