extension UInt8 {
  /// Whether this byte is one of the six that "blank" and "whitespace" mean: TAB, LF, VT, FF, CR
  /// and SPACE (chapter 08 "The linked region", chapter 11 §15). Other Unicode whitespace is not.
  var isBlankByte: Bool {
    switch self {
    case 0x09 ... 0x0D, 0x20:
      true
    default:
      false
    }
  }
}
