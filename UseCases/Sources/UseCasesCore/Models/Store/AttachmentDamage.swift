/// How a stored attachment fails to be the evidence its descriptor names.
enum AttachmentDamage: Equatable, Sendable, CustomStringConvertible {
  case missing
  case unreadable
  case wrongSize(expected: Int, found: Int)
  case wrongDigest

  var description: String {
    switch self {
    case .missing:
      "the blob is missing"
    case .unreadable:
      "the blob cannot be read"
    case let .wrongSize(expected, found):
      "the blob is \(found) bytes, not \(expected)"
    case .wrongDigest:
      "the blob is not the bytes its digest names"
    }
  }
}
