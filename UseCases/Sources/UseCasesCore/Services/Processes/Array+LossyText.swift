extension [UInt8] {
  /// The bytes as UTF-8 text, with U+FFFD for each invalid sequence (chapter 14 §10).
  var lossyUTF8Text: String {
    var decoder = UTF8()
    var iterator = makeIterator()
    var text = String.UnicodeScalarView()

    while true {
      switch decoder.decode(&iterator) {
      case let .scalarValue(scalar):
        text.append(scalar)
      case .error:
        text.append("\u{FFFD}")
      case .emptyInput:
        return String(text)
      }
    }
  }
}
