/// Text that is the same only when it is the same Unicode scalars: a composed `é` and `e` with a
/// combining accent are two names, as JSON says, and a Kelvin sign is not a `K`. Swift's own
/// `String` equality, hashing and ordering treat canonically equivalent text as equal.
struct ExactText: Hashable, Comparable, Sendable, ExpressibleByStringLiteral {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  init(stringLiteral value: String) {
    text = value
  }

  static func == (
    lhs: ExactText,
    rhs: ExactText,
  ) -> Bool {
    lhs.text.hasSameScalars(as: rhs.text)
  }

  static func < (
    lhs: ExactText,
    rhs: ExactText,
  ) -> Bool {
    lhs.text.precedesByScalars(rhs.text)
  }

  func hash(into hasher: inout Hasher) {
    for scalar in text.unicodeScalars {
      hasher.combine(scalar.value)
    }
  }
}
