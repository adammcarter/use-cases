/// What the nesting scan carries from one line to the next.
struct YAMLNestingState {
  private struct Entry {
    let column: Int
    let isSequence: Bool
  }

  private let limit: Int
  private var entries: [Entry] = []
  private var flowDepth = 0
  private var openQuote: Unicode.Scalar?
  private var blockScalarOwner: Int?
  private(set) var exceeded = false

  init(limit: Int) {
    self.limit = limit
  }

  mutating func read(_ line: [Unicode.Scalar]) {
    var position = 0

    if let quote = openQuote {
      position = closeQuote(
        quote,
        in: line,
        from: 0,
      )

      guard openQuote == nil else {
        return
      }
    } else if let owner = blockScalarOwner {
      let indent = line.prefix { $0 == " " }.count

      if indent == line.count || indent > owner {
        return
      }

      blockScalarOwner = nil
    }

    position = line.skippingSpaces(from: position)

    if flowDepth > 0 {
      scanFlow(
        line,
        from: position,
      )
    } else {
      scanBlock(
        line,
        from: position,
      )
    }
  }

  private mutating func scanBlock(
    _ line: [Unicode.Scalar],
    from start: Int,
  ) {
    var position = start

    if start == 0, line.isDocumentMarker {
      entries = []
      flowDepth = 0
      position = line.skippingSpaces(from: 3)
    }

    while position < line.count, line[position] != "#", !exceeded {
      position = line.skippingProperties(from: position)

      guard position < line.count, line[position] != "#" else {
        return
      }

      guard let next = scanEntry(
        line,
        at: position,
      ) else {
        return
      }

      position = next
    }
  }

  /// Reads one `-`, `?` or `key:` at a position and returns where reading carries on, or nil
  /// when the rest of the line is a value.
  private mutating func scanEntry(
    _ line: [Unicode.Scalar],
    at position: Int,
  ) -> Int? {
    if line.hasIndicator("-", at: position) || line.hasIndicator("?", at: position) {
      enter(
        column: position,
        isSequence: line[position] == "-",
      )

      return line.skippingSpaces(from: position + 1)
    }

    var valueStart = position

    if let end = line.keyEnd(from: position) {
      enter(
        column: position,
        isSequence: false,
      )
      valueStart = line.skippingProperties(from: line.skippingSpaces(from: end))
    }

    scanValue(
      line,
      from: valueStart,
    )

    return nil
  }

  private mutating func scanValue(
    _ line: [Unicode.Scalar],
    from start: Int,
  ) {
    guard start < line.count else {
      return
    }

    switch line[start] {
    case "[", "{":
      scanFlow(
        line,
        from: start,
      )
    case "\"", "'":
      _ = closeQuote(
        line[start],
        in: line,
        from: start + 1,
      )
    case "|", ">":
      blockScalarOwner = entries.last?.column ?? -1
    default:
      break
    }
  }

  private mutating func scanFlow(
    _ line: [Unicode.Scalar],
    from start: Int,
  ) {
    var position = start
    var atTokenStart = true

    while position < line.count, !exceeded {
      let scalar = line[position]

      if scalar == "#", position == start || line[position - 1] == " " {
        return
      }

      if scalar == "\"" || scalar == "'", atTokenStart {
        position = closeQuote(
          scalar,
          in: line,
          from: position + 1,
        )
        atTokenStart = false
        continue
      }

      if scalar == "]" || scalar == "}" {
        flowDepth = max(flowDepth - 1, 0)

        if flowDepth == 0 {
          return
        }
      } else if scalar == "[" || scalar == "{" {
        flowDepth += 1
        exceeded = entries.count + flowDepth > limit
      }

      atTokenStart = "[{,: \t".unicodeScalars.contains(scalar)
      position += 1
    }
  }

  private mutating func enter(
    column: Int,
    isSequence: Bool,
  ) {
    while let top = entries.last, top.column > column {
      entries.removeLast()
    }

    if let top = entries.last, top.column == column {
      if top.isSequence == isSequence {
        return
      }

      if top.isSequence {
        entries.removeLast()

        if let next = entries.last, next.column == column, !next.isSequence {
          return
        }
      }
    }

    entries.append(
      Entry(
        column: column,
        isSequence: isSequence,
      ),
    )
    exceeded = entries.count + flowDepth > limit
  }

  /// Skips a quoted scalar's body, leaving `openQuote` set when the line ends before it closes.
  private mutating func closeQuote(
    _ quote: Unicode.Scalar,
    in line: [Unicode.Scalar],
    from start: Int,
  ) -> Int {
    guard let after = line.positionAfterQuote(
      quote,
      from: start,
    ) else {
      openQuote = quote

      return line.count
    }

    openQuote = nil

    return after
  }
}
