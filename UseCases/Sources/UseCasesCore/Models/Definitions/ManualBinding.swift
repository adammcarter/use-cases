/// A link from a use case or a route to a place in the repository, written in YAML
/// (chapter 08). Markers are found in the code and have no entry here.
struct ManualBinding: Equatable, Sendable {
  let identifier: BindingIdentifier
  let locator: ManualLocator

  init(
    identifier: BindingIdentifier,
    locator: ManualLocator,
  ) {
    self.identifier = identifier
    self.locator = locator
  }

  /// Reads one item of `bindings`, which must say `kind: manual`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let kind = try object.requiredString("kind")

    guard kind == "manual" else {
      throw .unknownChoice(
        location: object.location(of: "kind"),
        text: kind,
      )
    }

    try self.init(
      identifier: object.requiredIdentifier(
        "id",
        parsing: BindingIdentifier.init(validating:),
      ),
      locator: ManualLocator(authored: object.requiredObject("locator")),
    )
  }
}
