public extension Unicode.Scalar {
  /// Whether a terminal or a reader may act on the character instead of showing it: the C0
  /// controls, DEL, the C1 controls and the bidirectional controls that reorder the text around
  /// them. White space is not one: a layout collapses it to a space.
  var isTerminalControl: Bool {
    guard !properties.isWhitespace else {
      return false
    }

    switch value {
    case 0x0 ... 0x1F, 0x7F ... 0x9F, 0x202A ... 0x202E, 0x2066 ... 0x2069:
      return true
    default:
      return false
    }
  }

  /// The scalar spelled out where it would be acted on: `\xNN` up to U+00FF, `\uNNNN` above,
  /// as names are escaped elsewhere. Any other scalar is itself.
  var escapedForDisplay: String {
    guard isTerminalControl else {
      return String(self)
    }

    let digits = String(value, radix: 16, uppercase: true)
    let width = value <= 0xFF ? 2 : 4

    return (value <= 0xFF ? "\\x" : "\\u")
      + String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}

public extension String {
  /// The first character a terminal would act on, if there is one.
  var firstTerminalControl: Unicode.Scalar? {
    unicodeScalars.first { scalar in
      scalar.isTerminalControl
    }
  }

  /// The text with every terminal control spelled out, so that showing it cannot move the
  /// cursor, hide a line or reorder what follows.
  var displayEscaped: String {
    unicodeScalars.map(\.escapedForDisplay).joined()
  }
}
