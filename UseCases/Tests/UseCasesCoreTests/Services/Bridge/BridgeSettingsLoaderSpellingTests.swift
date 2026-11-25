import Testing
@testable import UseCasesCore

struct BridgeSettingsLoaderSpellingTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  @Test(arguments: ["Use-Cases-Bridge.yml", "USE-CASES-BRIDGE.YML"])
  func `a bridge file spelled in another case is refused naming its spelling, on every system`(
    spelling: String,
  ) throws {
    try fixture.write(spelling, "schema_version: 1\n")

    let found = fixture.problems()

    #expect(found.count == 1)
    #expect(found.mentions("'\(spelling)' is not spelled use-cases-bridge.yml"))
  }

  @Test(.enabled(if: TemporaryDirectory.allowsNamesDifferingInCase))
  func `a lookalike beside the real bridge file is refused and the real one is still read`(
  ) throws {
    try fixture.write("Use-Cases-Bridge.yml", "schema_version: 1\n")
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\nextras: []\n")

    let found = fixture.problems()

    #expect(found.count == 2)
    #expect(found.mentions("'Use-Cases-Bridge.yml' is not spelled"))
    #expect(found.mentions("Additional properties"))
  }

  @Test
  func `a bridge file in a child scope spelled in another case is refused too`() throws {
    try fixture.write("pricing/use-cases.yml", "schema_version: 1\nprefix: pricing\n")
    try fixture.write("pricing/Use-Cases-Bridge.yml", "schema_version: 1\n")

    #expect(fixture.problems().mentions("'pricing/Use-Cases-Bridge.yml' is not spelled"))
  }
}
