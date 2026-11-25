/// What an authored YAML file, or a JSON document, holds once it is read (chapter 09 §14):
/// plain JSON-compatible values, with an object's members kept in authored order.
enum AuthoredValue: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case number(Double)
  case boolean(Bool)
  case null
  case array([AuthoredValue])
  case object([AuthoredMember])
}

/// One member of an object, in the place it was written.
struct AuthoredMember: Equatable, Sendable {
  let key: String
  let value: AuthoredValue
}
