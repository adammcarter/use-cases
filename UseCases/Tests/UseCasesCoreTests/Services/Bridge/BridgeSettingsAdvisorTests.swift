import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct BridgeSettingsAdvisorTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  private func warnings(_ text: String) throws -> [String] {
    try fixture.write("use-cases-bridge.yml", text)

    return try fixture.loaded().rootFileWarnings.map(\.description)
  }

  @Test
  func `validations written as an empty list is a warning`() throws {
    #expect(try warnings("schema_version: 1\nvalidations: []\n") == [
      "use-cases-bridge.yml: validations is empty: nothing is set up to verify",
    ])
  }

  @Test
  func `a file that leaves validations out says nothing`() throws {
    #expect(try warnings("schema_version: 1\n").isEmpty)
  }

  @Test
  func `a validation with no run command can only be read after verify start`() throws {
    let found = try warnings(BridgeFileSamples.validation())

    #expect(found.count == 1)
    #expect(found.first?.contains("validation 'unit-tests' has no run command") == true)
    #expect(found.first?.contains("verify --start") == true)
  }

  @Test(arguments: [
    "/usr/bin/true", "\\\\server\\share\\run", "C:\\tools\\run.exe", "c:/tools/run.exe",
  ])
  func `a run command by an absolute path warns of its portability`(executable: String) throws {
    let text = BridgeFileSamples.validation(
      lines: ["report: r.xml", "run: ['\(executable)', --flag]"],
    )

    let found = try warnings(text)

    #expect(found.count == 1)
    #expect(found.first?.contains("is an absolute path") == true)
    #expect(found.first?.contains("validation 'unit-tests'") == true)
  }

  @Test(arguments: ["swift", "scripts/test-all.sh", "./run", "c:run", "a:b", "{report}"])
  func `a bare name or a relative path says nothing`(executable: String) throws {
    let text = BridgeFileSamples.validation(
      lines: ["report: r.xml", "run: ['\(executable)']"],
    )

    #expect(try warnings(text).isEmpty)
  }

  @Test
  func `only the program is looked at, not its arguments`() throws {
    let text = BridgeFileSamples.validation(lines: ["run: [swift, /tmp/report.xml]"])

    #expect(try warnings(text).isEmpty)
  }

  @Test
  func `the full sample warns of its validation without a run command only`() throws {
    try fixture.directory.makeDirectory("scripts")

    let found = try warnings(BridgeFileSamples.full)

    #expect(found.count == 1)
    #expect(found.first?.contains("validation 'style' has no run command") == true)
  }

  @Test
  func `a file with a problem reports the problem and no warning`() throws {
    try fixture.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(transformer: "no-such-transformer"),
    )

    #expect(fixture.problems().count == 1)
  }

  @Test
  func `the settings of a file that only warns are still loaded`() throws {
    try fixture.write("use-cases-bridge.yml", BridgeFileSamples.validation())

    #expect(try fixture.loaded().bridge?.validations.count == 1)
  }

  @Test
  func `bridge warnings are kept apart from the load's own, so a run never carries them`(
  ) throws {
    try fixture.write("use-cases-bridge.yml", BridgeFileSamples.validation())

    #expect(try fixture.loaded().warnings.isEmpty)
  }
}
