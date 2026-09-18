/// The regular expressions `validateSkillAssets` runs, spelled out over UTF-16
/// code units so they read text exactly as V8 reads it: `\s` is JavaScript's
/// whitespace, `\b` is an ASCII word boundary, and a match never spans a
/// grapheme cluster the way Swift's own `Regex` would.
enum SkillText {
  /// `source.includes(needle)`, by code unit.
  static func contains(
    _ source: String,
    _ needle: String,
  ) -> Bool {
    let units = Array(source.utf16)
    let target = Array(needle.utf16)
    guard !target.isEmpty else {
      return true
    }
    guard units.count >= target.count else {
      return false
    }
    return (0 ... units.count - target.count).contains { start in
      units[start ..< start + target.count].elementsEqual(target)
    }
  }

  /// `text.split(/\s+/)`: every piece between runs of whitespace, empty
  /// pieces at either end kept.
  static func splitOnWhitespace(_ text: String) -> [String] {
    var pieces: [String] = []
    var current: [UInt16] = []
    var isInRun = false
    for unit in text.utf16 {
      if CodeUnits.isJavaScriptWhitespace(unit) {
        if !isInRun {
          pieces.append(CodeUnits.string(current))
          current = []
          isInRun = true
        }
      } else {
        current.append(unit)
        isInRun = false
      }
    }
    pieces.append(CodeUnits.string(current))
    return pieces
  }

  /// The first group of `/^---\n([\s\S]*?)\n---\n/`, or nil when the source
  /// does not open with frontmatter.
  static func frontmatter(_ source: String) -> String? {
    let units = Array(source.utf16)
    let fence: [UInt16] = [CodeUnits.hyphenMinus, CodeUnits.hyphenMinus, CodeUnits.hyphenMinus]
    let opening = fence + [CodeUnits.lineFeed]
    let closing = [CodeUnits.lineFeed] + fence + [CodeUnits.lineFeed]
    guard units.starts(with: opening) else {
      return nil
    }
    var end = opening.count
    while end + closing.count <= units.count {
      if units[end ..< end + closing.count].elementsEqual(closing) {
        return CodeUnits.string(units[opening.count ..< end])
      }
      end += 1
    }
    return nil
  }

  /// Every first group of the global `/`(?:use-cases|pnpm cli --)\s+([^`]+?)`/g`, in
  /// order, with the regex's own backtracking: when the whitespace run is
  /// followed straight by the closing backtick, the capture is the run's last
  /// character, so long as the run is two or more.
  static func cliCommandCaptures(_ source: String) -> [String] {
    let units = Array(source.utf16)
    var captures: [String] = []
    var start = 0
    while start < units.count {
      guard units[start] == backtick, let match = captureMatch(units, at: start) else {
        start += 1
        continue
      }
      captures.append(CodeUnits.string(units[match.capture]))
      start = match.end
    }
    return captures
  }

  /// Whether a forbidden claim appears anywhere in `source`.
  static func matches(
    _ claim: SkillForbiddenClaim,
    in source: String,
  ) -> Bool {
    let units = source.utf16.map(asciiLowercased)
    return claim.phrasings.contains { phrasing in
      units.indices.contains { start in
        guard !claim.isWordBounded || start == 0 || !isASCIIWord(units[start - 1]) else {
          return false
        }
        return matches(phrasing[...], units, at: start)
      }
    }
  }

  private static let backtick: UInt16 = 0x60

  private static let prefixes: [[UInt16]] = [Array("use-cases".utf16), Array("pnpm cli --".utf16)]

  private static func captureMatch(
    _ units: [UInt16],
    at start: Int,
  ) -> (capture: Range<Int>, end: Int)? {
    guard let prefix = prefixes.first(where: { prefix in
      units[(start + 1)...].starts(with: prefix)
    }) else {
      return nil
    }
    let whitespaceStart = start + 1 + prefix.count
    var afterWhitespace = whitespaceStart
    while afterWhitespace < units.count, CodeUnits.isJavaScriptWhitespace(units[afterWhitespace]) {
      afterWhitespace += 1
    }
    let runLength = afterWhitespace - whitespaceStart
    guard runLength >= 1, afterWhitespace < units.count else {
      return nil
    }
    guard units[afterWhitespace] != backtick else {
      guard runLength >= 2 else {
        return nil
      }
      return (afterWhitespace - 1 ..< afterWhitespace, afterWhitespace + 1)
    }
    guard let closing = units[(afterWhitespace + 1)...].firstIndex(of: backtick) else {
      return nil
    }
    return (afterWhitespace ..< closing, closing + 1)
  }

  /// One phrasing — word alternatives joined by `\s+` — matched at `position`.
  private static func matches(
    _ groups: ArraySlice<[String]>,
    _ units: [UInt16],
    at position: Int,
  ) -> Bool {
    guard let group = groups.first else {
      return true
    }
    return group.contains { word in
      let wordUnits = Array(word.utf16)
      guard units[position...].starts(with: wordUnits) else {
        return false
      }
      let next = position + wordUnits.count
      guard groups.count > 1 else {
        return true
      }
      var afterWhitespace = next
      while afterWhitespace < units.count,
            CodeUnits.isJavaScriptWhitespace(units[afterWhitespace])
      {
        afterWhitespace += 1
      }
      guard afterWhitespace > next else {
        return false
      }
      return matches(groups.dropFirst(), units, at: afterWhitespace)
    }
  }

  /// The `i` flag without `u`: only ASCII letters fold.
  private static func asciiLowercased(_ unit: UInt16) -> UInt16 {
    (0x41 ... 0x5A).contains(unit) ? unit + 0x20 : unit
  }

  private static func isASCIIWord(_ unit: UInt16) -> Bool {
    CodeUnits.isASCIILetter(unit) || CodeUnits.isASCIIDigit(unit) || unit == CodeUnits.lowLine
  }
}
