extension String {
  /// The text of bytes that are all ASCII, as the id characters of a marker are.
  init(asciiBytes bytes: ArraySlice<UInt8>) {
    var text = ""

    for byte in bytes {
      text.unicodeScalars.append(Unicode.Scalar(byte))
    }

    self = text
  }
}
