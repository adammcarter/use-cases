/// The span canonicalizer `ucase-span-lines-v2` (spec section 3).
///
/// Over the body lines strictly between markers: strip trailing spaces and
/// tabs, strip the common leading whitespace prefix, collapse blank-line runs
/// and drop leading and trailing blank lines, join with LF, end with exactly one
/// LF unless empty, and take sha256 over the UTF-8 bytes. Comments and relative
/// indentation survive, so a whole-block reindent does not move the hash.
public enum SpanCanonicalizer {
  /// CRLF and CR become LF (spec step 3).
  public static func normalizeNewlines(_ content: String) -> String {
    let units = Array(content.utf16)
    var normalized: [UInt16] = []
    normalized.reserveCapacity(units.count)
    var index = 0
    while index < units.count {
      let unit = units[index]
      index += 1
      guard unit == CodeUnits.carriageReturn else {
        normalized.append(unit)
        continue
      }
      normalized.append(CodeUnits.lineFeed)
      if index < units.count, units[index] == CodeUnits.lineFeed {
        index += 1
      }
    }
    return CodeUnits.string(normalized)
  }

  /// The canonical span text.
  public static func canonicalize(_ lines: [String]) -> String {
    let stripped = lines.map { line in
      CodeUnits.trimmingTrailingSpaceOrTab(Array(line.utf16))
    }
    let prefixLength = commonLeadingWhitespacePrefix(stripped).count
    let dedented = prefixLength == 0
      ? stripped
      : stripped.map { line in
        line.isEmpty ? line : Array(line.dropFirst(prefixLength))
      }
    let collapsed = collapseBlankLines(dedented)
    guard !collapsed.isEmpty else {
      return ""
    }
    var joined = Array(collapsed.joined(separator: [CodeUnits.lineFeed]))
    joined.append(CodeUnits.lineFeed)
    return CodeUnits.string(joined)
  }

  /// `sha256:<hex>` over the canonical span bytes (spec step 12).
  public static func hash(_ lines: [String]) -> String {
    MarkerDigest.sha256(canonicalize(lines))
  }

  private static func commonLeadingWhitespacePrefix(_ lines: [[UInt16]]) -> [UInt16] {
    var prefix: [UInt16]?
    for line in lines where !line.isEmpty {
      let current = Array(line.prefix(CodeUnits.spaceOrTabRun(line, from: 0)))
      guard let existing = prefix else {
        prefix = current
        continue
      }
      var shared = 0
      while shared < existing.count, shared < current.count, existing[shared] == current[shared] {
        shared += 1
      }
      prefix = Array(existing.prefix(shared))
      if shared == 0 {
        break
      }
    }
    return prefix ?? []
  }

  private static func collapseBlankLines(_ lines: [[UInt16]]) -> [[UInt16]] {
    var collapsed: [[UInt16]] = []
    for line in lines {
      if line.isEmpty {
        if let last = collapsed.last, !last.isEmpty {
          collapsed.append([])
        }
        continue
      }
      collapsed.append(line)
    }
    if collapsed.last?.isEmpty == true {
      collapsed.removeLast()
    }
    return collapsed
  }
}
