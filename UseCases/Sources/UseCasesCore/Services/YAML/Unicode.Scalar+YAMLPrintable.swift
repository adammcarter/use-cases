extension Unicode.Scalar {
  /// Whether YAML allows the character in a text without an escape, and no reader reads it as a
  /// line break or drops it: the tab is left out because it is escaped, and so are the line and
  /// paragraph separators, `U+0085` and the byte order mark.
  var isYAMLPrintable: Bool {
    switch value {
    case 0x20 ... 0x7E, 0xA0 ... 0x2027, 0x202A ... 0xD7FF, 0xE000 ... 0xFEFE, 0xFF00 ... 0xFFFD,
         0x10000 ... 0x10FFFF:
      true
    default:
      false
    }
  }
}
