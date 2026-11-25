/// One situation a use case promises to handle (chapter 02 "scenarios").
struct Scenario: Equatable, Sendable {
  let identifier: ScenarioIdentifier
  let given: [String]
  let when: [String]
  let then: [String]

  init(
    identifier: ScenarioIdentifier,
    given: [String],
    when: [String],
    then: [String],
  ) {
    self.identifier = identifier
    self.given = given
    self.when = when
    self.then = then
  }

  /// Reads one item of `scenarios`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      identifier: object.requiredIdentifier(
        "id",
        parsing: ScenarioIdentifier.init(validating:),
      ),
      given: object.strings("given"),
      when: object.strings("when"),
      then: object.strings("then"),
    )
  }
}
