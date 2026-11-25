/// How one or more scenarios are proved (chapter 06). It never says how tests are started or
/// how their output is read.
struct ValidationRoute: Equatable, Sendable {
  /// What an omitted `gates_verification` means.
  static let defaultGatesVerification = true

  let identifier: RouteIdentifier
  let type: ValidationType

  /// The scenarios the route proves, in the order written. They are ids as written: whether
  /// each names a scenario of the use case is checked against the use case.
  let covers: [ScenarioIdentifier]

  /// Whether the route counts towards the use case's overall status.
  let gatesVerification: Bool
  let procedure: Procedure?
  let bindings: [ManualBinding]
  let resources: [RouteResource]

  init(
    identifier: RouteIdentifier,
    type: ValidationType,
    covers: [ScenarioIdentifier],
    gatesVerification: Bool,
    procedure: Procedure?,
    bindings: [ManualBinding],
    resources: [RouteResource],
  ) {
    self.identifier = identifier
    self.type = type
    self.covers = covers
    self.gatesVerification = gatesVerification
    self.procedure = procedure
    self.bindings = bindings
    self.resources = resources
  }

  /// Reads one item of `validation`, filling in the default for `gates_verification`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var resources: [RouteResource] = []

    for resource in try object.objects("resources") {
      try resources.append(RouteResource(authored: resource))
    }

    var procedure: Procedure?

    if let written = try object.optionalObject("procedure") {
      procedure = try Procedure(authored: written)
    }

    try self.init(
      identifier: object.requiredIdentifier(
        "id",
        parsing: RouteIdentifier.init(validating:),
      ),
      type: ValidationType(authored: object.requiredObject("type")),
      covers: object.identifiers(
        "covers",
        parsing: ScenarioIdentifier.init(validating:),
      ),
      gatesVerification: object.optionalBoolean("gates_verification")
        ?? Self.defaultGatesVerification,
      procedure: procedure,
      bindings: object.manualBindings("bindings"),
      resources: resources,
    )
  }
}
