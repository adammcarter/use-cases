import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct BridgeSettingsLoaderTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.directory.makeDirectory("scripts")
  }

  private func load(_ text: String) throws -> LoadedWorkspace {
    try fixture.write("use-cases-bridge.yml", text)

    return try fixture.loaded()
  }

  private func problems(_ text: String) throws -> [String] {
    try fixture.write("use-cases-bridge.yml", text)

    return fixture.problems()
  }

  // MARK: - A valid file

  @Test
  func `a workspace with no bridge file has no bridge settings`() throws {
    #expect(try fixture.loaded().bridge == nil)
  }

  @Test
  func `a valid file is read into its links and validations in the order written`() throws {
    let bridge = try #require(load(BridgeFileSamples.full).bridge)

    #expect(bridge.links.map(\.transformer) == [.bundled("test-names")])
    #expect(bridge.validations.map(\.identifier.text) == ["unit-tests", "style"])

    let unit = try #require(bridge.validations.first)
    #expect(unit.report == "unit.xml")
    #expect(unit.run == ["node", "--test", "--test-reporter-destination={report}"])
    #expect(try unit.workingDirectory == WorkspacePath(validating: "scripts"))
    #expect(unit.transformer == .bundled("junit"))
    #expect(unit.timeoutSeconds == 900)
    #expect(unit.settings != nil)
  }

  @Test
  func `an entry with nothing optional has none of it`() throws {
    let bridge = try #require(load(BridgeFileSamples.full).bridge)
    let style = try #require(bridge.validations.last)

    #expect(style.report == nil)
    #expect(style.run == nil)
    #expect(style.workingDirectory == nil)
    #expect(style.settings == nil)
    #expect(style.timeoutSeconds == nil)
  }

  @Test
  func `a file with only schema_version is valid and has nothing`() throws {
    let bridge = try #require(load("schema_version: 1\n").bridge)

    #expect(bridge.links.isEmpty)
    #expect(bridge.validations.isEmpty)
  }

  @Test(arguments: [
    "junit", "go-test-json", "cargo-test", "swift-test", "swift-testing", "cucumber-messages",
    "exit-code", "test-names",
  ])
  func `every bundled transformer name is taken`(name: String) throws {
    let bridge = try #require(load(BridgeFileSamples.validation(transformer: name)).bridge)

    #expect(bridge.validations.first?.transformer == .bundled(name))
  }

  @Test
  func `a project program that exists is taken by its path`() throws {
    try fixture.write("tools/read-junit", "#!/bin/sh\n")

    let bridge = try #require(load(BridgeFileSamples.validation(transformer: "tools/read-junit"))
      .bridge)

    #expect(try bridge.validations.first?
      .transformer == .program(WorkspacePath(validating: "tools/read-junit")))
  }

  @Test
  func `a program that is not executable still loads: launching it is a run error`(
  ) throws {
    try fixture.write("tools/links", "#!/bin/sh\n")

    #expect(try problems(BridgeFileSamples.validation(transformer: "tools/links")).isEmpty)
  }

  // MARK: - Problems

  @Test
  func `a file that is not YAML is refused at its line`() throws {
    let found = try problems("schema_version: 1\nvalidations: [\n")

    #expect(found.count == 1)
    #expect(found.first?.hasPrefix("use-cases-bridge.yml:") == true)
  }

  @Test
  func `a duplicate YAML key is refused`() throws {
    let found = try problems("schema_version: 1\nschema_version: 1\n")

    #expect(found.first?.contains("duplicate key 'schema_version'") == true)
  }

  @Test
  func `an unknown field is refused by the schema`() throws {
    let found = try problems("schema_version: 1\nextras: []\n")

    #expect(found.first?
      .contains("Additional properties are not allowed ('extras' was unexpected)") == true)
  }

  @Test(arguments: ["2", "0", "\"1\""])
  func `an unsupported schema_version is refused`(version: String) throws {
    #expect(try !problems("schema_version: \(version)\n").isEmpty)
  }

  @Test(arguments: ["record", "nul", "com1", "lpt9", "aux", "Upper"])
  func `a validation id that is reserved or off the grammar is refused at its place`(
    id: String,
  ) throws {
    let found = try problems(BridgeFileSamples.validation(id: id))

    #expect(found.mentions("validations/0/id"))
  }

  @Test
  func `two validations with one id are refused, naming both places`() throws {
    let text = """
    schema_version: 1
    validations:
      - id: a
        transformer: junit
      - id: b
        transformer: junit
      - id: a
        transformer: junit

    """

    let found = try problems(text)

    #expect(found.count == 1)
    #expect(found.first?.contains("'a' is used more than once") == true)
    #expect(found.first?.contains("validations/0/id and validations/2/id") == true)
  }

  @Test(arguments: ["build/unit.xml", "../unit.xml", "a\\\\b.xml"])
  func `a report that is a path is told as one`(report: String) throws {
    let found = try problems(BridgeFileSamples
      .validation(lines: ["report: \(report.debugDescription)"]))

    #expect(found.count == 1)
    #expect(found.first?.contains("a file or folder name, not a path") == true)
    #expect(found.first?.contains("validations/0/report") == true)
  }

  @Test(arguments: [
    "..",
    ".hidden",
    "unit.",
    "con.xml",
    "unit tests.xml",
    String(repeating: "x", count: 65),
  ])
  func `a report that is not a portable name is refused by the schema at its place`(
    report: String,
  ) throws {
    let found = try problems(BridgeFileSamples
      .validation(lines: ["report: \(report.debugDescription)"]))

    #expect(found.mentions("validations/0/report"))
  }

  @Test(arguments: ["unit.xml", "a", "A-b_c.1.xml", "report"])
  func `a portable report name is taken`(report: String) throws {
    #expect(try problems(BridgeFileSamples.validation(lines: ["report: \(report)"])).isEmpty)
  }

  @Test
  func `a working_dir that is not there is refused`() throws {
    let found = try problems(BridgeFileSamples.validation(lines: ["working_dir: missing"]))

    #expect(found.count == 1)
    #expect(found.first?
      .contains("working_dir must be an existing folder inside the project") == true)
    #expect(found.first?.contains("validations/0/working_dir") == true)
  }

  @Test
  func `a working_dir that is a file is refused`() throws {
    try fixture.write("scripts/check.sh", "true\n")

    let found = try problems(BridgeFileSamples.validation(lines: ["working_dir: scripts/check.sh"]))

    #expect(found.first?
      .contains("working_dir must be an existing folder inside the project") == true)
    #expect(found.first?.contains("is not a folder") == true)
  }

  @Test
  func `a working_dir that is a symlink is refused, even to a folder inside`() throws {
    try fixture.directory.symlink("link", to: "scripts")

    let found = try problems(BridgeFileSamples.validation(lines: ["working_dir: link"]))

    #expect(found.first?.contains("symlink") == true)
  }

  @Test(arguments: ["..", "../x", "/tmp", ".use-cases", ".use-cases/runs", "./scripts", "a//b"])
  func `a working_dir off the project or inside the store is refused by the schema`(
    directory: String,
  ) throws {
    try fixture.directory.makeDirectory(".use-cases/runs")

    let found = try problems(BridgeFileSamples.validation(lines: ["working_dir: \(directory)"]))

    #expect(found.mentions("validations/0/working_dir"))
  }

  @Test
  func `a working_dir that is a folder inside is taken`() throws {
    #expect(try problems(BridgeFileSamples.validation(lines: ["working_dir: scripts"])).isEmpty)
  }

  @Test
  func `an unknown bundled transformer is refused at its place`() throws {
    let found = try problems(BridgeFileSamples.validation(transformer: "no-such-tool"))

    #expect(found.count == 1)
    #expect(found.first?
      .contains("unknown bundled transformer 'no-such-tool' at validations/0/transformer") == true)
  }

  @Test
  func `an unknown link transformer is refused at its place`() throws {
    let found = try problems("schema_version: 1\nlinks:\n  - transformer: nope\n")

    #expect(found.first?
      .contains("unknown bundled transformer 'nope' at links/0/transformer") == true)
  }

  @Test(arguments: ["../outside/tool", "/bin/sh", "tools/../../x", "C:/tool"])
  func `a program path off the workspace is refused by the schema`(path: String) throws {
    let found = try problems(BridgeFileSamples.validation(transformer: path))

    #expect(found.mentions("is not allowed at validations/0/transformer"))
  }

  @Test
  func `a program that is not there is refused`() throws {
    let found = try problems(BridgeFileSamples.validation(transformer: "tools/missing"))

    #expect(found.count == 1)
    #expect(found.first?.contains("transformer program 'tools/missing' does not exist") == true)
  }

  @Test
  func `a program that is a symlink out of the workspace is refused`() throws {
    let outside = try TemporaryDirectory()
    try outside.write("tool", "#!/bin/sh\n")
    try fixture.directory.symlink("tools/tool", to: outside.location(of: "tool").path)

    let found = try problems(BridgeFileSamples.validation(transformer: "tools/tool"))

    #expect(found.first?.contains("is outside the workspace") == true)
  }

  @Test
  func `every problem of a file is reported, sorted, and the workspace is INVALID`() throws {
    let text = """
    schema_version: 1
    links:
      - transformer: nope
    validations:
      - id: a
        working_dir: missing
        transformer: junit
      - id: a
        transformer: tools/gone

    """

    let found = try problems(text)

    #expect(found.count == 4)
    // By file, then position, then code: a report reads the same however it was found.
    let keywords = [
      "transformer program",
      "working_dir must",
      "used more than once",
      "unknown bundled",
    ]
    #expect(keywords.map(found.firstIndexMentioning) == [0, 1, 2, 3])
  }

  // MARK: - Where the file is

  @Test
  func `a bridge file in a child scope is root-only`() throws {
    try fixture.write("pricing/use-cases.yml", "schema_version: 1\nprefix: pricing\n")
    try fixture.write("pricing/use-cases-bridge.yml", "schema_version: 1\n")

    let found = fixture.problems()

    #expect(found.count == 1)
    #expect(found.first?
      .hasPrefix("pricing/use-cases-bridge.yml: bridge settings are root-only") == true)
  }

  @Test
  func `a bridge file in a folder that is not a scope is just a file`() throws {
    try fixture.write("tools/use-cases-bridge.yml", "schema_version: 1\n")

    #expect(try fixture.loaded().bridge == nil)
  }

  @Test
  func `a bridge file that is a folder is refused`() throws {
    try fixture.directory.makeDirectory("use-cases-bridge.yml")

    let found = fixture.problems()

    #expect(found.first?.contains("regular file") == true)
    #expect(found.first?.contains("a folder") == true)
  }

  @Test
  func `a bridge file that is a symlink is refused, never followed`() throws {
    try fixture.write("elsewhere.yml", "schema_version: 1\n")
    try fixture.directory.symlink("use-cases-bridge.yml", to: "elsewhere.yml")

    let found = fixture.problems()

    #expect(found.first?.contains("a symlink") == true)
  }

  @Test
  func `a problem in the bridge file is reported beside a problem elsewhere`() throws {
    try fixture.write("use-cases/broken.yml", "use_cases: 3\n")
    try fixture.write("use-cases-bridge.yml", "schema_version: 7\n")

    let found = fixture.problems()

    #expect(found.mentions("use-cases-bridge.yml: "))
    #expect(found.mentions("use-cases/broken.yml: "))
  }

  @Test
  func `loading reads the file and runs nothing`() throws {
    let marker = fixture.directory.location(of: "ran")
    let text = BridgeFileSamples
      .validation(lines: ["run: [touch, \(marker.path.debugDescription)]"])

    _ = try load(text)

    #expect(!FileManager.default.fileExists(atPath: marker.path))
  }
}
