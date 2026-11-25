/// Reading one line of a YAML file, as scalars, without looking at the lines around it.
extension [Unicode.Scalar] {
  func skippingSpaces(from start: Int) -> Int {
    var position = start

    while position < count, self[position] == " " || self[position] == "\t" {
      position += 1
    }

    return position
  }

  /// Skips anchors and tags, which each run to the next space.
  func skippingProperties(from start: Int) -> Int {
    var position = start

    while position < count, self[position] == "&" || self[position] == "!" {
      while position < count, self[position] != " ", self[position] != "\t" {
        position += 1
      }

      position = skippingSpaces(from: position)
    }

    return position
  }

  /// Whether an indicator (`-`, `?` or `:`) stands at a position, followed by a space or the end.
  func hasIndicator(
    _ indicator: Unicode.Scalar,
    at position: Int,
  ) -> Bool {
    guard position < count, self[position] == indicator else {
      return false
    }

    return position + 1 == count || self[position + 1] == " " || self[position + 1] == "\t"
  }

  /// Whether the line is a `---` or `...` marker.
  var isDocumentMarker: Bool {
    guard count >= 3 else {
      return false
    }

    let marker = Array(prefix(3))
    let isMarker = marker == ["-", "-", "-"] || marker == [".", ".", "."]

    return isMarker && (count == 3 || self[3] == " " || self[3] == "\t")
  }

  /// The position after the closing quote of a quoted scalar whose body starts at `start`, or
  /// nil when the line ends before it closes.
  func positionAfterQuote(
    _ quote: Unicode.Scalar,
    from start: Int,
  ) -> Int? {
    var position = start

    while position < count {
      if quote == "\"", self[position] == "\\" {
        position += 2
      } else if self[position] != quote {
        position += 1
      } else if quote == "'", position + 1 < count, self[position + 1] == "'" {
        position += 2
      } else {
        return position + 1
      }
    }

    return nil
  }

  /// Where a `key:` ends, if a mapping key starts at `start`.
  func keyEnd(from start: Int) -> Int? {
    guard !"[{|>".unicodeScalars.contains(self[start]) else {
      return nil
    }

    if self[start] == "\"" || self[start] == "'" {
      guard let after = positionAfterQuote(self[start], from: start + 1) else {
        return nil
      }

      let colon = skippingSpaces(from: after)

      return hasIndicator(":", at: colon) ? colon + 1 : nil
    }

    for position in start ..< count {
      if hasIndicator(":", at: position) {
        return position + 1
      }

      if self[position] == "#", position > start, self[position - 1] == " " {
        return nil
      }
    }

    return nil
  }
}
