/// One step from the top of a document down to a value: an object's key or an array's index.
/// Keys are the same only when they are the same Unicode scalars.
enum SchemaPathStep: Hashable, Comparable, Sendable {
  case key(String)
  case index(Int)

  /// The step as the text of a path.
  var text: String {
    switch self {
    case let .key(key): key
    case let .index(index): String(index)
    }
  }

  static func == (
    lhs: SchemaPathStep,
    rhs: SchemaPathStep,
  ) -> Bool {
    switch (lhs, rhs) {
    case let (.index(left), .index(right)): left == right
    case let (.key(left), .key(right)): left.hasSameScalars(as: right)
    default: false
    }
  }

  func hash(into hasher: inout Hasher) {
    switch self {
    case let .index(index):
      hasher.combine(0)
      hasher.combine(index)
    case let .key(key):
      hasher.combine(1)
      hasher.combine(ExactText(key))
    }
  }

  /// Indexes come in numeric order, 2 before 10, and before keys; keys by scalar value.
  static func < (
    lhs: SchemaPathStep,
    rhs: SchemaPathStep,
  ) -> Bool {
    switch (lhs, rhs) {
    case let (.index(left), .index(right)): left < right
    case let (.key(left), .key(right)): left.precedesByScalars(right)
    case (.index, .key): true
    case (.key, .index): false
    }
  }
}
