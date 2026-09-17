/// JavaScript's `String.prototype.toLowerCase`.
///
/// Per scalar it is Unicode's full lowercase mapping, which Swift exposes. The
/// one context-sensitive rule is Final_Sigma: a capital sigma that ends a word
/// lowers to `ς`, not `σ`. Swift's `lowercased()` does not apply it, so
/// `.ΑΣ` would lower to `.ασ` there and `.ας` in JavaScript.
enum JavaScriptCase {
  private static let capitalSigma: Unicode.Scalar = "\u{03A3}"
  private static let finalSigma: Unicode.Scalar = "\u{03C2}"

  static func lowercased(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    var result = String.UnicodeScalarView()
    for (index, scalar) in scalars.enumerated() {
      if scalar == capitalSigma, isFinalSigma(scalars, at: index) {
        result.append(finalSigma)
      } else {
        result.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
      }
    }
    return String(result)
  }

  /// Preceded by a cased letter and not followed by one, skipping
  /// case-ignorable characters on both sides (Unicode SpecialCasing).
  private static func isFinalSigma(
    _ scalars: [Unicode.Scalar],
    at index: Int,
  ) -> Bool {
    var before = index - 1
    while before >= 0, scalars[before].properties.isCaseIgnorable {
      before -= 1
    }
    guard before >= 0, scalars[before].properties.isCased else {
      return false
    }
    var after = index + 1
    while after < scalars.count, scalars[after].properties.isCaseIgnorable {
      after += 1
    }
    return after >= scalars.count || !scalars[after].properties.isCased
  }
}
