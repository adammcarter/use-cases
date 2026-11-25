struct SentinelFinder: SentinelFinding {
  /// The bytes `@use-case:`.
  private static let sentinel = Array("@use-case:".utf8)

  /// How many letters, digits and underscores after an id run are kept to name in a warning.
  private static let followingWordLimit = 40

  /// The bytes `end`, which with the spaces or tabs after it turn a sentinel into an end.
  private static let endWord = Array("end".utf8)

  func holdsSentinel(_ bytes: [UInt8]) -> Bool {
    nextSentinel(
      in: bytes,
      from: 0,
    ) != nil
  }

  func sentinels(
    in bytes: [UInt8],
    lines: LineIndex,
  ) -> [MarkerSentinel] {
    var found: [MarkerSentinel] = []
    var cursor = 0

    while let offset = nextSentinel(
      in: bytes,
      from: cursor,
    ) {
      let sentinel = read(
        at: offset,
        in: bytes,
        lines: lines,
      )

      found.append(sentinel)
      cursor = sentinel.tokenRange.upperBound
    }

    return found
  }

  /// The offset of the next `@use-case:` at or after `start`.
  private func nextSentinel(
    in bytes: [UInt8],
    from start: Int,
  ) -> Int? {
    let length = Self.sentinel.count
    var offset = start

    while offset + length <= bytes.count {
      if bytes[offset] == Self.sentinel[0], hasSentinel(
        in: bytes,
        at: offset,
      ) {
        return offset
      }

      offset += 1
    }

    return nil
  }

  private func hasSentinel(
    in bytes: [UInt8],
    at offset: Int,
  ) -> Bool {
    for (index, expected) in Self.sentinel.enumerated() where bytes[offset + index] != expected {
      return false
    }

    return true
  }

  /// Reads the sentinel at `offset`: end or start, then its id.
  private func read(
    at offset: Int,
    in bytes: [UInt8],
    lines: LineIndex,
  ) -> MarkerSentinel {
    let afterSentinel = offset + Self.sentinel.count
    let afterEnd = endSeparatorEnd(
      in: bytes,
      from: afterSentinel,
    )
    let identifierStart = afterEnd ?? afterSentinel
    let runEnd = identifierRunEnd(
      in: bytes,
      from: identifierStart,
    )
    let identifierEnd = trimmedEnd(
      in: bytes,
      from: identifierStart,
      runEnd: runEnd,
    )

    let wordEnd = wordEnd(
      in: bytes,
      from: runEnd,
    )

    return MarkerSentinel(
      kind: afterEnd == nil ? .start : .end,
      identifier: String(asciiBytes: bytes[identifierStart ..< identifierEnd]),
      tokenRange: offset ..< (wordEnd > runEnd ? wordEnd : identifierEnd),
      line: lines.line(containing: offset),
      followingWord: String(
        asciiBytes: bytes[runEnd ..< min(wordEnd, runEnd + Self.followingWordLimit)],
      ),
    )
  }

  /// Where the id of an end sentinel begins: after `end` and every space or tab that follows it.
  /// `nil` when `end` and at least one space or tab do not follow, so this is a start sentinel.
  private func endSeparatorEnd(
    in bytes: [UInt8],
    from start: Int,
  ) -> Int? {
    let afterWord = start + Self.endWord.count

    guard afterWord < bytes.count, bytes[start ..< afterWord].elementsEqual(Self.endWord) else {
      return nil
    }

    var cursor = afterWord

    while cursor < bytes.count, bytes[cursor] == 0x20 || bytes[cursor] == 0x09 {
      cursor += 1
    }

    return cursor > afterWord ? cursor : nil
  }

  /// Where the longest run of `a-z 0-9 . # -` from `start` ends.
  private func identifierRunEnd(
    in bytes: [UInt8],
    from start: Int,
  ) -> Int {
    var end = start

    while end < bytes.count, Self.isIdentifierByte(bytes[end]) {
      end += 1
    }

    return end
  }

  /// Where the id ends: the end of its run, less any trailing `-` and `.`.
  private func trimmedEnd(
    in bytes: [UInt8],
    from start: Int,
    runEnd: Int,
  ) -> Int {
    var end = runEnd

    while end > start, bytes[end - 1] == 0x2D || bytes[end - 1] == 0x2E {
      end -= 1
    }

    return end
  }

  /// Where the run of ASCII letters, digits and underscores that starts at `start` ends; `start`
  /// itself when none does.
  private func wordEnd(
    in bytes: [UInt8],
    from start: Int,
  ) -> Int {
    var end = start

    while end < bytes.count, Self.isWordByte(bytes[end]) {
      end += 1
    }

    return end
  }

  private static func isWordByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x30 ... 0x39, 0x5F:
      true
    default:
      false
    }
  }

  private static func isIdentifierByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 0x61 ... 0x7A, 0x30 ... 0x39, 0x2E, 0x23, 0x2D:
      true
    default:
      false
    }
  }
}
