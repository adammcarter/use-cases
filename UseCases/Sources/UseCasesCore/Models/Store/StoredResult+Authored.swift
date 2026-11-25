extension StoredResult {
  /// Reads a record of a version this core reads, after it passed the result schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      envelopeOf: object,
      detail: StoredResultDetail(authored: object),
    )
  }

  /// Reads the envelope every record version keeps: use case, route, fingerprint and status.
  init(envelopeOf object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      envelopeOf: object,
      detail: nil,
    )
  }

  private init(
    envelopeOf object: AuthoredObject,
    detail: StoredResultDetail?,
  ) throws(AuthoredShapeError) {
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
      verdict: object.requiredChoice(
        "status",
        as: Verdict.self,
      ),
      detail: detail,
    )
  }
}
