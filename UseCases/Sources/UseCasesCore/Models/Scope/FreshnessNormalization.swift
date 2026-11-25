/// A kind of difference that content comparison may ignore before fingerprinting (chapter 04).
enum FreshnessNormalization: String, CaseIterable, Hashable, Sendable {
  case lineEndings = "line-endings"
  case whitespace
}
