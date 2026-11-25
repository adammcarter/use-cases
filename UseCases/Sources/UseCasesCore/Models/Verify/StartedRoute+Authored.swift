extension StartedRoute {
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      useCase: object.requiredIdentifier(
        "use_case",
        parsing: UseCaseIdentifier.init(validating:),
      ),
      route: object.requiredIdentifier(
        "route",
        parsing: RouteIdentifier.init(validating:),
      ),
      fingerprint: object.requiredFingerprint("fingerprint"),
    )
  }
}
