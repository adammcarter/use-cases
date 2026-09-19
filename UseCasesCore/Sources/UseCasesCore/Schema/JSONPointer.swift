/// RFC 6901 JSON pointers, used for both diagnostic paths and `$ref` fragments.
enum JSONPointer {
  /// Escape one path segment: `~` becomes `~0` and `/` becomes `~1`.
  static func escape(_ segment: String) -> String {
    segment
      .replacingOccurrences(of: "~", with: "~0")
      .replacingOccurrences(of: "/", with: "~1")
  }

  /// Undo ``escape(_:)``.
  static func unescape(_ segment: String) -> String {
    segment
      .replacingOccurrences(of: "~1", with: "/")
      .replacingOccurrences(of: "~0", with: "~")
  }

  /// Follow `pointer` into `document`, or nil when it does not lead anywhere.
  static func resolve(
    _ pointer: String,
    in document: JSONValue,
  ) -> JSONValue? {
    guard !pointer.isEmpty else {
      return document
    }
    guard pointer.hasPrefix("/") else {
      return nil
    }
    var current = document
    for segment in pointer.dropFirst().components(separatedBy: "/") {
      let key = unescape(segment)
      if let member = current.objectValue?[key] {
        current = member
      } else if let index = Int(key), let items = current.arrayValue,
                items.indices.contains(index)
      {
        current = items[index]
      } else {
        return nil
      }
    }
    return current
  }
}
