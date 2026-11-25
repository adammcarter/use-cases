/// Line endings first, then whitespace (chapter 11 §16), on text only: strict UTF-8 is text, and
/// anything else is binary and passes through exactly. Nothing is decoded, so a byte-order mark
/// stays and no character set is guessed (§17). A CR, LF or blank byte never occurs inside a
/// multibyte UTF-8 sequence, so working on bytes cannot damage a character.
struct ContentNormalizer: ContentNormalizing {
  private let normalizesLineEndings: Bool
  private let removesWhitespace: Bool

  /// Normalizes the way the rules say, however many times each is listed and in any order.
  init(ignoring rules: [FreshnessNormalization]) {
    normalizesLineEndings = rules.contains(.lineEndings)
    removesWhitespace = rules.contains(.whitespace)
  }

  /// Normalizes the way a freshness policy says.
  init(policy: FreshnessPolicy) {
    self.init(ignoring: policy.ignoring)
  }

  func normalized(_ bytes: [UInt8]) -> [UInt8] {
    guard var run = normalizationRun(), bytes.isStrictUTF8 else {
      return bytes
    }

    return run.normalize(bytes)
  }

  func normalizationRun() -> NormalizationRun? {
    guard normalizesLineEndings || removesWhitespace else {
      return nil
    }

    return NormalizationRun(
      normalizesLineEndings: normalizesLineEndings,
      removesWhitespace: removesWhitespace,
    )
  }
}
