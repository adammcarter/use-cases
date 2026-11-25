/// What kind of proof a validation route is (chapter 06 "Type"). It classifies coverage only.
enum ValidationType: Hashable, Sendable {
  case unit
  case integration
  case contract
  case snapshot
  case userInterface
  case e2e
  case acceptance
  case performance

  /// A kind the built-in list lacks, named by the author.
  case custom(name: IdentifierSegment)

  /// Reads a route's `type` mapping.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let kind = try object.requiredString("kind")

    switch kind {
    case "unit": self = .unit
    case "integration": self = .integration
    case "contract": self = .contract
    case "snapshot": self = .snapshot
    case "ui": self = .userInterface
    case "e2e": self = .e2e
    case "acceptance": self = .acceptance
    case "performance": self = .performance
    case "custom":
      self = try .custom(
        name: object.requiredIdentifier(
          "name",
          parsing: IdentifierSegment.init(validating:),
        ),
      )
    default:
      throw .unknownChoice(
        location: object.location(of: "kind"),
        text: kind,
      )
    }
  }
}
