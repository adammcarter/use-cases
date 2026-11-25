/// A setting only the workspace root's `use-cases.yml` may hold (chapter 04 "Root-only policy",
/// chapter 09 §8). A child scope that writes one is INVALID.
enum RootOnlySetting: String, CaseIterable, Sendable {
  case freshness
  case discovery
  case signOff = "sign_off"

  /// The key as it is written in `use-cases.yml`.
  var key: String {
    rawValue
  }
}
