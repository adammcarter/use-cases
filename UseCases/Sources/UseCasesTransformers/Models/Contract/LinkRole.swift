/// Whether a link points at code that implements a behaviour or at a test that validates it.
enum LinkRole: String, Codable, Equatable, Sendable {
  case implementation
  case validation
}
