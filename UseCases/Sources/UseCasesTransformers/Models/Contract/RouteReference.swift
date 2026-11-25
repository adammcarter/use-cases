/// A route of a resolved use case, as far as a links transformer needs it.
struct RouteReference: Decodable, Equatable, Sendable {
  let id: String
}
