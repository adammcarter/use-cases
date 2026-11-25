import Testing
@testable import UseCasesCore

struct ProcedureTests {
  private func procedure(_ json: String) throws -> Procedure {
    try Procedure(authored: AuthoredObject(authored(json), at: "procedure"))
  }

  @Test
  func `setup, steps and reset are read in the order written`() throws {
    let procedure = try procedure(
      #"{"setup":["Launch."],"steps":["Sign in.","Observe."],"reset":["Quit."]}"#,
    )

    #expect(procedure.setup == ["Launch."])
    #expect(procedure.steps == ["Sign in.", "Observe."])
    #expect(procedure.reset == ["Quit."])
  }

  @Test
  func `setup and reset may be left out`() throws {
    let procedure = try procedure(#"{"steps":["Sign in."]}"#)

    #expect(procedure.setup.isEmpty)
    #expect(procedure.reset.isEmpty)
  }

  @Test
  func `a procedure with no steps key is refused`() {
    #expect(
      throws: AuthoredShapeError.missing(location: "procedure.steps"),
    ) {
      try procedure(#"{"setup":["Launch."]}"#)
    }
  }
}
