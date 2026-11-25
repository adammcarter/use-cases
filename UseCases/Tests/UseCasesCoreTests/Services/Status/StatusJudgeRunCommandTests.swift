import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct StatusJudgeRunCommandTests {
  private let fixture: StatusFixture

  init() throws {
    fixture = try StatusFixture()
  }

  @Test
  func `with no bridge settings nothing has a run command`() throws {
    #expect(try !fixture.status().hasRunCommand)
  }

  @Test
  func `a validation with a run command makes verify run the step`() throws {
    try fixture.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)

    #expect(try fixture.status().hasRunCommand)
  }

  @Test
  func `validations without one leave verify start the step`() throws {
    try fixture.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(transformer: "exit-code"),
    )

    #expect(try !fixture.status().hasRunCommand)
  }
}
