/// One use case as it is written in a definition file (chapter 02), with the defaults filled in.
///
/// The id is the local one; the full id is composed with the scopes' prefixes and the file's
/// (``UseCaseIdentifier``). Nothing in it comes from outside the file.
struct UseCaseDefinition: Equatable, Sendable {
  let localIdentifier: IdentifierSegment
  let title: String
  let description: String?
  let valueTier: ValueTier?
  let intent: String?
  let outOfScope: [String]

  /// In the order written.
  let scenarios: [Scenario]

  /// The `validation` routes, in the order written.
  let routes: [ValidationRoute]

  /// The use case's own manual bindings, which point at its implementation.
  let bindings: [ManualBinding]
  let approval: Approval?

  init(
    localIdentifier: IdentifierSegment,
    title: String,
    description: String?,
    valueTier: ValueTier?,
    intent: String?,
    outOfScope: [String],
    scenarios: [Scenario],
    routes: [ValidationRoute],
    bindings: [ManualBinding],
    approval: Approval?,
  ) {
    self.localIdentifier = localIdentifier
    self.title = title
    self.description = description
    self.valueTier = valueTier
    self.intent = intent
    self.outOfScope = outOfScope
    self.scenarios = scenarios
    self.routes = routes
    self.bindings = bindings
    self.approval = approval
  }

  /// Reads one item of `use_cases`. Whatever is not in the schema is left alone: the schema is
  /// what refuses an unknown field.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var scenarios: [Scenario] = []

    for scenario in try object.objects("scenarios") {
      try scenarios.append(Scenario(authored: scenario))
    }

    var routes: [ValidationRoute] = []

    for route in try object.objects("validation") {
      try routes.append(ValidationRoute(authored: route))
    }

    var approval: Approval?

    if let written = try object.optionalObject("approved") {
      approval = try Approval(authored: written)
    }

    try self.init(
      localIdentifier: object.requiredIdentifier(
        "id",
        parsing: IdentifierSegment.init(validating:),
      ),
      title: object.requiredString("title"),
      description: object.optionalString("description"),
      valueTier: object.optionalChoice(
        "value_tier",
        as: ValueTier.self,
      ),
      intent: object.optionalString("intent"),
      outOfScope: object.strings("out_of_scope"),
      scenarios: scenarios,
      routes: routes,
      bindings: object.manualBindings("bindings"),
      approval: approval,
    )
  }
}
