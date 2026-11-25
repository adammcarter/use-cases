/// A link the core sends with a results job. A transformer echoes `key` and reads the rest.
struct RequestLink: Decodable, Equatable, Sendable {
  let key: String
  let useCase: String
  let route: String?
  let binding: String
  let role: LinkRole
  let file: String
  /// Nil means the whole file.
  let range: LineRange?

  private enum CodingKeys: String, CodingKey {
    case key
    case useCase = "use_case"
    case route
    case binding
    case role
    case file
    case range
  }
}
