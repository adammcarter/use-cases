/// Which node a position in the file holds; a position met twice is an alias being expanded.
struct YAMLNodeIdentity: Hashable {
  enum Kind {
    case scalar
    case sequence
    case mapping
  }

  let kind: Kind
  let line: Int
  let column: Int
}
