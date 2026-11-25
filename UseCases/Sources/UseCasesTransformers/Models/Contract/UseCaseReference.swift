/// A resolved use case in a request, as far as a links transformer needs it: its id and the ids of
/// its validation routes.
struct UseCaseReference: Decodable, Equatable, Sendable {
  let id: String
  let routes: [RouteReference]

  init(
    id: String,
    routes: [RouteReference] = [],
  ) {
    self.id = id
    self.routes = routes
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(
      String.self,
      forKey: .id,
    )
    routes = try container.decodeIfPresent(
      [RouteReference].self,
      forKey: .routes,
    ) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case routes = "validation"
  }
}
