extension RouteFingerprints {
  /// Every route with its current fingerprint, as status judges it (chapter 12 §27). Empty when
  /// the workspace is INVALID.
  var current: [RouteAtFingerprint] {
    routes.compactMap { live in
      guard
        let useCase = try? UseCaseIdentifier(validating: live.useCase),
        let route = try? RouteIdentifier(validating: live.route),
        let fingerprint = try? RouteFingerprint(validating: live.fingerprint)
      else {
        return nil
      }

      return RouteAtFingerprint(
        useCase: useCase,
        route: route,
        fingerprint: fingerprint,
      )
    }
  }
}
