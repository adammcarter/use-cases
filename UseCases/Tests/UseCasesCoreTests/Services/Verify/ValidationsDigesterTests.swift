import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct ValidationsDigesterTests {
  private let digester = ValidationsDigester()

  private func validations(_ bridge: String) throws -> [BridgeValidation] {
    let fixture = try VerifyFixture(bridge: bridge)

    return try #require(fixture.resolved().workspace.bridge?.validations)
  }

  @Test
  func `the digest is 64 lowercase hex digits and the same for the same settings`() throws {
    let bridge = BridgeFileSamples.validation(lines: ["report: unit.xml"])

    let first = try digester.digest(of: validations(bridge))
    let second = try digester.digest(of: validations(bridge))

    #expect(first == second)
    #expect(first.count == 64)
    #expect(first.allSatisfy { digit in
      "0123456789abcdef".contains(digit)
    })
  }

  @Test(arguments: [
    ["report: other.xml"],
    ["report: unit.xml", "working_dir: scripts"],
    ["report: unit.xml", "timeout_seconds: 5"],
    ["report: unit.xml", "run: [echo]"],
    ["report: unit.xml", "settings: { find: pattern }"],
  ])
  func `any setting of a validation changes the digest`(lines: [String]) throws {
    let base = try digester.digest(
      of: validations(BridgeFileSamples.validation(lines: ["report: unit.xml"])),
    )

    let fixture = try VerifyFixture(
      bridge: BridgeFileSamples.validation(lines: lines),
    )
    try fixture.freshness.workspace.directory.makeDirectory("scripts")
    let changed = try digester.digest(
      of: #require(fixture.resolved().workspace.bridge?.validations),
    )

    #expect(changed != base)
  }

  @Test
  func `the transformer changes the digest`() throws {
    let first = try digester.digest(of: validations(BridgeFileSamples.validation()))
    let second = try digester.digest(
      of: validations(BridgeFileSamples.validation(transformer: "exit-code")),
    )

    #expect(first != second)
  }

  @Test
  func `no validations have a digest too, which is not that of some validation`() throws {
    let none = digester.digest(of: [])
    let some = try digester.digest(of: validations(BridgeFileSamples.validation()))

    #expect(none.count == 64)
    #expect(none != some)
  }
}
