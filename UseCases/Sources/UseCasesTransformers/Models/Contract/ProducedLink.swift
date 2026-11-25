/// A link a links transformer found. The core turns its lines into exact bytes.
struct ProducedLink: Encodable, Equatable, Sendable {
  let useCase: String
  /// Present for validation links, absent for implementation links.
  let route: String?
  let binding: String
  let role: LinkRole
  let file: String
  let range: LineRange

  private enum CodingKeys: String, CodingKey {
    case useCase = "use_case"
    case route
    case binding
    case role
    case file
    case range
  }
}
