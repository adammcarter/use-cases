/// Authored input once it is read: the value, and what to call it in a message.
struct AuthoredInput: Equatable, Sendable {
  /// `stdin`, or the path as typed.
  let name: String
  let value: AuthoredValue
}
