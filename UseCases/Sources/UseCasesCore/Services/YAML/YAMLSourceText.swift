/// The text of an authored file, addressed the way libyaml's marks address it: by line, and by
/// column counted in Unicode scalars.
struct YAMLSourceText: Equatable, Sendable {
  private let scalars: [Unicode.Scalar]
  private let lineStarts: [Int]

  init(_ text: String) {
    let scalars = Array(text.unicodeScalars)
    var starts = [0]
    var position = 0

    while position < scalars.count {
      let scalar = scalars[position]

      if scalar == "\r", position + 1 < scalars.count, scalars[position + 1] == "\n" {
        position += 1
      }

      if Self.isBreak(scalar) {
        starts.append(position + 1)
      }

      position += 1
    }

    self.scalars = scalars
    lineStarts = starts
  }

  /// How many lines the text has.
  var lineCount: Int {
    lineStarts.count
  }

  /// The scalars of a line (counting from 1), without its line break.
  func scalars(ofLine line: Int) -> [Unicode.Scalar] {
    guard line >= 1, line <= lineStarts.count else {
      return []
    }

    let start = lineStarts[line - 1]
    var end = line < lineStarts.count ? lineStarts[line] : scalars.count

    while end > start, Self.isBreak(scalars[end - 1]) {
      end -= 1
    }

    return Array(scalars[start ..< end])
  }

  /// The position a mark points at, or nil when it lies outside the text.
  func index(
    line: Int,
    column: Int,
  ) -> Int? {
    guard line >= 1, line <= lineStarts.count, column >= 1 else {
      return nil
    }

    let index = lineStarts[line - 1] + column - 1

    return index <= scalars.count ? index : nil
  }

  /// The line (counting from 1) that a position is on.
  func line(at index: Int) -> Int {
    var low = 0
    var high = lineStarts.count

    while low < high {
      let middle = (low + high) / 2

      if lineStarts[middle] <= index {
        low = middle + 1
      } else {
        high = middle
      }
    }

    return max(low, 1)
  }

  /// Skips the anchors in front of a node, and says where a tag begins if one follows.
  func properties(startingAt index: Int) -> YAMLNodeProperties {
    var position = index

    while let scalar = scalar(at: position) {
      if scalar == "&" {
        position = skippingWhitespaceAndComments(from: skippingName(from: position))
      } else if scalar == "!" {
        return YAMLNodeProperties(
          contentStart: position,
          tagIndex: position,
        )
      } else {
        break
      }
    }

    return YAMLNodeProperties(
      contentStart: position,
      tagIndex: nil,
    )
  }

  /// The position just after a plain scalar's last character, found by matching its text against
  /// the source, where a line break in the source may be a space in the text.
  func plainScalarEnd(
    of value: String,
    startingAt index: Int,
  ) -> Int? {
    var position = index

    for expected in value.unicodeScalars where !Self.isWhitespace(expected) {
      position = skippingWhitespace(from: position)

      guard scalar(at: position) == expected else {
        return nil
      }

      position += 1
    }

    return position
  }

  /// Whether the text that begins at `index` starts with a byte order mark, written itself or as
  /// the escape `\uFEFF` or `\U0000FEFF` in double quotes. A quoted text starts after its quote,
  /// and a literal or folded block on the line after its header.
  func textStartsWithByteOrderMark(at index: Int) -> Bool {
    switch scalar(at: index) {
    case "\""?:
      scalar(at: index + 1) == Self.mark || escapesByteOrderMark(at: index + 1)
    case "'"?:
      scalar(at: index + 1) == Self.mark
    case "|"?, ">"?:
      blockStartsWithByteOrderMark(headerAt: index)
    default:
      scalar(at: index) == Self.mark
    }
  }

  private static let mark: Unicode.Scalar = "\u{FEFF}"

  private func escapesByteOrderMark(at index: Int) -> Bool {
    guard scalar(at: index) == "\\" else {
      return false
    }

    let digits: Int

    switch scalar(at: index + 1) {
    case "u":
      digits = 4
    case "U":
      digits = 8
    default:
      return false
    }

    let written = (0 ..< digits).compactMap { offset in
      scalar(at: index + 2 + offset)
    }

    return written.count == digits
      && UInt32(String(String.UnicodeScalarView(written)), radix: 16) == Self.mark.value
  }

  private func blockStartsWithByteOrderMark(headerAt index: Int) -> Bool {
    var position = index

    while let scalar = scalar(at: position), !Self.isBreak(scalar) {
      position += 1
    }

    // The first content line follows the header; a blank one first means the text starts with a
    // line break instead.
    position = skippingBreak(from: position)

    while scalar(at: position) == " " {
      position += 1
    }

    return scalar(at: position) == Self.mark
  }

  private func skippingBreak(from index: Int) -> Int {
    if scalar(at: index) == "\r", scalar(at: index + 1) == "\n" {
      return index + 2
    }

    return scalar(at: index).map { _ in
      index + 1
    } ?? index
  }

  /// The comment that follows on the same line, set apart by white space.
  func comment(after index: Int) -> YAMLComment? {
    var start = index

    while let scalar = scalar(at: start), scalar == " " || scalar == "\t" {
      start += 1
    }

    guard start > index, scalar(at: start) == "#" else {
      return nil
    }

    var end = start

    while let scalar = scalar(at: end), !Self.isBreak(scalar) {
      end += 1
    }

    var written = scalars[start ..< end]

    while let last = written.last, Self.isWhitespace(last) {
      written = written.dropLast()
    }

    return YAMLComment(
      text: String(String.UnicodeScalarView(written)),
      line: line(at: start),
    )
  }

  /// The scalar at a position, or nil outside the text.
  func scalar(at index: Int) -> Unicode.Scalar? {
    index >= 0 && index < scalars.count ? scalars[index] : nil
  }

  private func skippingWhitespace(from index: Int) -> Int {
    var position = index

    while let scalar = scalar(at: position), Self.isWhitespace(scalar) {
      position += 1
    }

    return position
  }

  private func skippingWhitespaceAndComments(from index: Int) -> Int {
    var position = skippingWhitespace(from: index)

    while scalar(at: position) == "#" {
      while let scalar = scalar(at: position), !Self.isBreak(scalar) {
        position += 1
      }

      position = skippingWhitespace(from: position)
    }

    return position
  }

  private func skippingName(from index: Int) -> Int {
    var position = index

    while let scalar = scalar(at: position), !Self.isWhitespace(scalar) {
      position += 1
    }

    return position
  }

  private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}": true
    default: false
    }
  }

  private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || isBreak(scalar)
  }
}

/// What stands in front of a node's own text: its anchors, and where a tag begins if it has one.
struct YAMLNodeProperties: Equatable, Sendable {
  let contentStart: Int
  let tagIndex: Int?
}

/// A comment found in the source, with the line it is on.
struct YAMLComment: Equatable, Sendable {
  let text: String
  let line: Int
}
