/// How much a use case matters (chapter 02 `value_tier`), most first.
enum ValueTier: String, CaseIterable, Sendable {
  case critical
  case core
  case supporting
}
