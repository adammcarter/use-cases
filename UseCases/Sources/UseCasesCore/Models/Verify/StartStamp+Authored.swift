extension StartStamp {
  /// Reads a stamp of version 1, after it passed the start schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var selected: [IdentifierSegment] = []
    for (index, text) in try object.strings("selected").enumerated() {
      do {
        try selected.append(IdentifierSegment(validating: text))
      } catch {
        throw .invalidIdentifier(
          location: "selected[\(index)]",
          error,
        )
      }
    }

    var routes: [StartedRoute] = []
    for route in try object.objects("routes") {
      try routes.append(StartedRoute(authored: route))
    }

    try self.init(
      identifier: object.requiredRunIdentifier("run_id"),
      startedAt: object.requiredString("started_at"),
      openedBy: object.requiredChoice(
        "opened_by",
        as: RunOpener.self,
      ),
      selected: selected,
      validationsDigest: object.requiredString("validations_sha256"),
      routes: routes,
      files: object.textMembers("files"),
    )
  }
}
