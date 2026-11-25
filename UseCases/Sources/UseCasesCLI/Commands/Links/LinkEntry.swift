import UseCasesCore

/// One link in the links document, in the shape a transformer receives. A route that is `nil`
/// is left out of the document, not written as null.
struct LinkEntry: Encodable {
  let key: String
  let source: String
  let useCase: String

  /// Present for a validation link only.
  let route: String?
  let binding: String
  let role: String
  let file: String
  let range: LineRange

  enum CodingKeys: String, CodingKey {
    case key
    case source
    case useCase = "use_case"
    case route
    case binding
    case role
    case file
    case range
  }

  init(_ link: ResolvedLink) {
    key = link.key
    source = link.source.rawValue
    useCase = link.useCase
    route = link.route
    binding = link.binding
    role = link.role.rawValue
    file = link.file
    range = LineRange(
      start: link.startLine,
      end: link.endLine,
    )
  }
}
