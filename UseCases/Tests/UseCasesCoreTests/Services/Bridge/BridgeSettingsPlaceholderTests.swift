import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// Braces in a run command (chapter 10 §8): `{report}` is the one placeholder, a near miss of it
/// is refused, and every other word in braces is plain text.
struct BridgeSettingsPlaceholderTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  private func load(_ text: String) throws -> LoadedWorkspace {
    try fixture.write("use-cases-bridge.yml", text)

    return try fixture.loaded()
  }

  private func problems(_ text: String) throws -> [String] {
    try fixture.write("use-cases-bridge.yml", text)

    return fixture.problems()
  }

  /// A run line with the argument as one YAML single-quoted scalar, so it is read as written.
  private func runLine(_ argument: String) -> String {
    let quoted = argument.replacingOccurrences(
      of: "'",
      with: "''",
    )

    return "run: [sh, -c, '\(quoted)']"
  }

  @Test
  func `an argument with a shell brace group is accepted and kept as given`() throws {
    let argument = "false || { echo failed; }"

    let bridge = try #require(load(BridgeFileSamples.validation(lines: [runLine(argument)])).bridge)

    #expect(bridge.validations.first?.run == ["sh", "-c", argument])
  }

  @Test
  func `a shell variable in braces is accepted and kept untouched`() throws {
    let argument = "echo ${HOME}"

    let bridge = try #require(load(BridgeFileSamples.validation(lines: [runLine(argument)])).bridge)

    #expect(bridge.validations.first?.run == ["sh", "-c", argument])
  }

  @Test
  func `a mistyped placeholder is refused, naming it and the one that is known`() throws {
    let found = try problems(
      BridgeFileSamples.validation(lines: ["run: [swift, test, '{reprot}']"]),
    )

    #expect(found == [
      "use-cases-bridge.yml: validations/0/run/2: unknown placeholder {reprot}; "
        + "{report} is the only one",
    ])
  }

  @Test
  func `the known placeholder is accepted beside the text around it`() throws {
    let bridge = try #require(load(BridgeFileSamples.validation(
      lines: ["run: [sh, -c, 'true || { echo {report}; }']"],
    )).bridge)

    #expect(bridge.validations.first?.run == ["sh", "-c", "true || { echo {report}; }"])
  }

  /// What the file says about one argument: `nil` when it loads, else the placeholder named.
  @Test(arguments: [
    ("{ }", nil),
    ("{}", nil),
    ("{a b}", nil),
    (#"{"k": 1}"#, nil),
    ("${HOME}", nil),
    ("${report}", nil),
    ("{1st}", nil),
    ("{a-b}", nil),
    ("{report}", nil),
    ("{a_1_b2}", nil),
    ("{_a}", nil),
    ("${a} {b}", nil),
    ("{name}", nil),
    ("{print}", nil),
    ("{p}", nil),
    ("{port}", nil),
    ("{repo}", nil),
    ("{export}", nil),
    ("{import}", nil),
    ("{xreportx}", nil),
    ("{Report}", "{Report}"),
    ("{REPORT}", "{REPORT}"),
    ("{reports}", "{reports}"),
    ("{repot}", "{repot}"),
    ("{eport}", "{eport}"),
    ("{reportt}", "{reportt}"),
    ("x{reprot}y", "{reprot}"),
    ("{{reprot}}", "{reprot}"),
  ] as [(String, String?)])
  func `only a near miss of the placeholder is refused, and every other word in braces loads`(
    argument: String,
    refused: String?,
  ) throws {
    let found = try problems(BridgeFileSamples.validation(lines: [runLine(argument)]))

    if let refused {
      #expect(found.count == 1)
      #expect(found.first?.contains("unknown placeholder \(refused);") == true)
    } else {
      #expect(found.isEmpty)
    }
  }

  /// A run argument as the core launches it, with this run's report path.
  private func launched(_ run: [String]) -> [String] {
    ProcessRequest(
      arguments: run,
      workingDirectory: URL(fileURLWithPath: "/"),
      reportPath: "/runs/r1/reports/unit",
      timeout: .seconds(1),
    ).launchArguments
  }

  @Test(arguments: [
    "awk '{print}' input.txt",
    "jq '{name}' input.json",
    "sed -n '/x/{p}' input.txt",
  ])
  func `a shell idiom with a word in braces loads and reaches the command unchanged`(
    argument: String,
  ) throws {
    let bridge = try #require(load(BridgeFileSamples.validation(lines: [runLine(argument)])).bridge)
    let run = try #require(bridge.validations.first?.run)

    #expect(run == ["sh", "-c", argument])
    #expect(launched(run) == ["sh", "-c", argument])
  }

  @Test
  func `the placeholder beside a word in braces is still replaced, and the word kept`() throws {
    let bridge = try #require(load(BridgeFileSamples.validation(
      lines: [runLine("awk '{print}' {report}")],
    )).bridge)
    let run = try #require(bridge.validations.first?.run)

    #expect(launched(run) == ["sh", "-c", "awk '{print}' /runs/r1/reports/unit"])
  }
}
