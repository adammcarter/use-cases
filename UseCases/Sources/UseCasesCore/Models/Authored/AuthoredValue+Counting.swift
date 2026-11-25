extension AuthoredValue {
  /// How many values this one is made of, counted as the reader's limit counts them: every
  /// scalar, list and mapping, and every key.
  var valueCount: Int {
    switch self {
    case let .array(items):
      items.reduce(1) { total, item in
        total + item.valueCount
      }
    case let .object(members):
      members.reduce(1) { total, member in
        total + 1 + member.value.valueCount
      }
    default:
      1
    }
  }
}
