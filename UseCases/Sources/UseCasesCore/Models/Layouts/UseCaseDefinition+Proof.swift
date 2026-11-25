extension UseCaseDefinition {
  /// How the use case is proven, in words, once each: the kinds of the routes that gate it, in
  /// the order written.
  var provenBy: [String] {
    var words: [String] = []

    for route in routes where route.gatesVerification {
      let kind = route.words

      if !words.contains(kind) {
        words.append(kind)
      }
    }

    return words
  }
}

private extension ValidationRoute {
  /// How the route is told under PROVEN BY: its kind, and for a route performed by following a
  /// procedure, the first step of it.
  var words: String {
    guard type == .acceptance, let step = procedure?.steps.first else {
      return type.words
    }

    var action = step.withoutOuterWhitespace

    while action.hasSuffix(".") {
      action.removeLast()
    }

    return "\(type.words): \(action)"
  }
}
