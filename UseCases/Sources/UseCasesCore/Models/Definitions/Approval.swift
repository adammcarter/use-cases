/// The sign-off of a use case's promise (chapter 02 `approved`, chapter 21): who, on which day,
/// and a fingerprint of its words then. The core writes it; nobody writes it by hand.
struct Approval: Equatable, Sendable {
  let approver: String

  /// The day, written `YYYY-MM-DD` and naming a day that exists.
  let day: String

  /// The fingerprint of the promise at the time: 64 hexadecimal digits.
  let behaviour: String

  init(
    approver: String,
    day: String,
    behaviour: String,
  ) {
    self.approver = approver
    self.day = day
    self.behaviour = behaviour
  }

  /// Reads the `approved` mapping.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      approver: object.requiredString("by"),
      day: object.requiredDay("on"),
      behaviour: object.requiredString("behaviour"),
    )
  }
}
