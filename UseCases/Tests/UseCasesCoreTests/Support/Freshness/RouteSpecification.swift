@testable import UseCasesCore

/// What a hand-built route input is made of besides its links and resources: the words of the
/// use case and the scenarios the route covers, which are exactly its `covers`.
struct RouteSpecification {
  let useCase: String
  let route: String
  let intent: String
  let scenarios: [Scenario]
  let type: ValidationType

  /// The steps of the route's procedure; `nil` for a route without one.
  let procedure: [String]?
}
