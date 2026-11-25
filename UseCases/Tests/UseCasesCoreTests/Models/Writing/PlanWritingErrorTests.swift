import Testing
@testable import UseCasesCore

struct PlanWritingErrorTests {
  @Test(arguments: [
    (PlanWritingError.exists(path: "a.yml"), "a.yml already exists, so it is not overwritten"),
    (PlanWritingError.missing(path: "a.yml"), "a.yml is not a file here"),
    (
      PlanWritingError.obstructed(path: "use-cases", reason: "it is a file, not a folder"),
      "use-cases cannot be used: it is a file, not a folder",
    ),
    (
      PlanWritingError.unwritable(location: "/w/a.yml", reason: "Permission denied"),
      "/w/a.yml cannot be written: Permission denied",
    ),
  ])
  func `each failure is one line that names the file`(
    error: PlanWritingError,
    message: String,
  ) {
    #expect(error.message == message)
  }
}
