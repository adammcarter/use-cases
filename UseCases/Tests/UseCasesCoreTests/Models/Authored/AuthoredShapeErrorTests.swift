import Testing
@testable import UseCasesCore

struct AuthoredShapeErrorTests {
  @Test(
    arguments: [
      (AuthoredShapeError.notAnObject(location: "a"), "a: this must be a mapping"),
      (AuthoredShapeError.missing(location: "a.b"), "a.b: this is required"),
      (
        AuthoredShapeError.wrongType(location: "x[1]", expected: "a list"),
        "x[1]: this must be a list",
      ),
      (
        AuthoredShapeError.unknownChoice(location: "tier", text: "vital"),
        "tier: 'vital' is not one of the values this field allows",
      ),
      (
        AuthoredShapeError.invalidDate(location: "on", text: "x"),
        "on: 'x' is not a day written YYYY-MM-DD",
      ),
      (
        AuthoredShapeError.invalidPosition(location: "s", .lineBelowOne(0)),
        "s: line 0 is below 1; lines count from 1",
      ),
      (
        AuthoredShapeError.invalidPosition(location: "s", .columnBelowOne(-1)),
        "s: column -1 is below 1; columns count from 1",
      ),
      (AuthoredShapeError.missing(location: ""), "this is required"),
    ],
  )
  func `an error reads as its place, then its reason`(
    case example: (error: AuthoredShapeError, text: String),
  ) {
    #expect(example.error.description == example.text)
  }

  @Test
  func `an id, path or pattern error brings the reason of its own type`() {
    let identity = AuthoredShapeError.invalidIdentifier(
      location: "id",
      .empty,
    )
    let path = AuthoredShapeError.invalidPath(
      location: "file",
      .absolute("/x"),
    )
    let pattern = AuthoredShapeError.invalidPattern(
      location: "pattern",
      .doubleStarNotWholeSegment("a**", within: "a**"),
    )

    #expect(identity.description == "id: '' is not a valid id: an id cannot be empty")
    #expect(path.description.hasPrefix("file: '/x' is not a valid path"))
    #expect(pattern.description.hasPrefix("pattern: 'a**' is not a valid pattern"))
  }

  @Test
  func `the location is the place without the reason`() {
    let error = AuthoredShapeError.invalidDate(
      location: "approved.on",
      text: "x",
    )

    #expect(error.location == "approved.on")
  }
}
