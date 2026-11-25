extension StoreJSONValue {
  /// The JSON an authored value prints as: a transformer's `settings` go to it unchanged
  /// (chapter 10 §6).
  init(_ value: AuthoredValue) {
    switch value {
    case let .string(text):
      self = .string(text)
    case let .integer(number):
      self = .integer(number)
    case let .number(number):
      self = .number(number)
    case let .boolean(flag):
      self = .boolean(flag)
    case .null:
      self = .null
    case let .array(items):
      self = .array(items.map(StoreJSONValue.init))
    case let .object(members):
      self = .object(
        members.map { member in
          StoreJSONMember(
            key: member.key,
            value: StoreJSONValue(member.value),
          )
        },
      )
    }
  }
}
