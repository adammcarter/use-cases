extension RouteKey {
  /// How a message names the route.
  var subject: String {
    "route '\(route.text)' of use case '\(useCase.text)'"
  }
}
