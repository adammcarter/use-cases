/// One member of an object the store's writers print, in the place it was given. The writer
/// sorts members by key, so the place carries no meaning.
public struct StoreJSONMember: Equatable, Sendable {
  /// The name of the member.
  public let key: String

  /// What the member holds.
  public let value: StoreJSONValue

  /// A member of an object.
  public init(
    key: String,
    value: StoreJSONValue,
  ) {
    self.key = key
    self.value = value
  }
}
