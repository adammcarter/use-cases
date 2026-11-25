/// The sign-off gate (chapter 04 "Root-only policy", chapter 16 §10): the gate holds a use case
/// whose promise is not approved as it reads now. Without the setting, approvals are recorded
/// and shown, and never gate.
enum SignOffRequirement: String, Sendable {
  case required
}
