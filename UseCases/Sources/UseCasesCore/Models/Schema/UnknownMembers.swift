/// What a checker does with an object member its schema does not list, where the schema says
/// `additionalProperties: false`.
enum UnknownMembers: Sendable {
  /// The member breaks the schema. This is what a writer must obey.
  case refuse

  /// The member is ignored, and every constraint on the members the schema lists still holds. A
  /// reader of a version it supports does this (chapter 12 §25).
  case ignore
}
