import Testing
@testable import UseCasesCore

struct UseCaseRemoverWarningTests {
  @Test
  func `the warnings of the warner it is given are the ones it reports`() throws {
    let fixture = try BatchFixture()
    let remover = UseCaseRemover(
      editor: DefinitionFileEditor(),
      warner: MockStillMarkedWarning(),
    )

    let change = try remover.plan(
      removing: "app.dark.toggle",
      in: fixture.loaded(),
      links: [],
    )

    #expect(change.warnings == ["marked: app.dark.toggle in 0 links"])
  }
}
