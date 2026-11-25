extension AuthoredValue {
  /// Whether any text in this value, or any key, starts with a byte order mark (U+FEFF). YAML
  /// readers drop one there, so authored text may not start with one (chapter 09 §14).
  var hasTextStartingWithByteOrderMark: Bool {
    switch self {
    case let .string(text):
      text.unicodeScalars.first == "\u{FEFF}"
    case let .array(items):
      items.contains { item in
        item.hasTextStartingWithByteOrderMark
      }
    case let .object(members):
      members.contains { member in
        member.key.unicodeScalars.first == "\u{FEFF}"
          || member.value.hasTextStartingWithByteOrderMark
      }
    default:
      false
    }
  }
}
