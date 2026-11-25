import UseCasesCore

/// One route in the status document (`cli-status.schema.json`, `route`). Its note keeps whole run
/// ids.
struct StatusRouteEntry: Encodable {
  let route: String
  let gates: Bool
  let linked: Bool
  let status: String
  let note: String

  init(_ route: RouteStatus) {
    self.route = route.identifier
    gates = route.gates
    linked = route.isLinked
    status = route.status.rawValue
    note = route.explanation.text(shortening: nil)
  }
}
