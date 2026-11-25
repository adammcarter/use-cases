/// The resolved links of a workspace, grouped the way routes use them (chapter 11 §33):
/// implementation links per use case, validation links per route.
struct GroupedLinks: Sendable {
  private let implementation: [UseCaseIdentifier: [ResolvedLink]]
  private let validation: [RouteKey: [ResolvedLink]]

  init(_ links: [ResolvedLink]) {
    var implementation: [UseCaseIdentifier: [ResolvedLink]] = [:]
    var validation: [RouteKey: [ResolvedLink]] = [:]

    for link in links {
      guard let route = link.identity.route else {
        implementation[link.identity.useCase, default: []].append(link)
        continue
      }

      let key = RouteKey(
        useCase: link.identity.useCase,
        route: route,
      )
      validation[key, default: []].append(link)
    }

    self.implementation = implementation
    self.validation = validation
  }

  /// The links that point at the code a use case is built in.
  func implementationLinks(of useCase: UseCaseIdentifier) -> [ResolvedLink] {
    implementation[useCase] ?? []
  }

  /// The links that prove one route.
  func validationLinks(of route: RouteKey) -> [ResolvedLink] {
    validation[route] ?? []
  }
}
