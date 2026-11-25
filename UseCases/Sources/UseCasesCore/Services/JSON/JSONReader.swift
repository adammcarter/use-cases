/// Reads strict JSON (RFC 8259) into an ``AuthoredValue``.
struct JSONReader: JSONReading {
  func read(_ text: String) throws(JSONReadingError) -> AuthoredValue {
    var parser = JSONParser(text: text)

    return try parser.parseDocument()
  }
}
