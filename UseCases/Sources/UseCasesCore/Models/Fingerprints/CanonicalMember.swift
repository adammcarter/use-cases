/// One member of an object, in the place it was given.
struct CanonicalMember: Sendable {
  let key: String
  let value: CanonicalValue
}
