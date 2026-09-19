import Foundation
import Testing

/// The seam itself, under test.
///
/// Every black-box test in the oracle reaches the binary through ``CliBinary``.
/// If that indirection silently stopped being an indirection — if it ignored
/// `UC_BIN`, or quietly fell back to the default build when the named binary
/// was missing — the whole suite would keep passing while testing the wrong
/// thing, and a port would look green on evidence it never produced.
///
/// So the seam is pinned here: the default really is the Swift build, `UC_BIN`
/// really is honoured, a `UC_BIN` that cannot run fails loudly, and stdout that
/// is not JSON fails naming the command.
///
/// One faithfulness note. `tests/blackbox/harness.test.ts` asserts the default
/// is a path outside this repository and does so by deleting and setting
/// `process.env.UC_BIN` around each case. Swift Testing runs a suite in one
/// process in parallel, where `setenv` is unsafe and would be seen by every
/// other test, so the override is passed to ``CliBinary/resolved(override:)``
/// instead — and the default under test is the Swift build, because that is
/// what this repository's oracle defaults to.
struct HarnessTests {
  /// A stand-in binary: the seam has to be provable without either real one.
  static func fakeBinary(
    _ directory: TemporaryDirectory,
    body: String,
  ) throws -> String {
    try directory.writeScript("fake-use-cases", body: body).path
  }

  static let versionEnvelope = """
  {"command":"version","ok":true,"schema_version":1,"protocol_version":1,\
  "complete":true,"data":{},"diagnostics":[],"context":{}}
  """

  @Test
  func `with UC_BIN unset it drives the built Swift CLI and returns a v1 envelope`()
    async throws
  {
    let binary = try CliBinary.resolved(override: nil)
    #expect(binary.overridden == false)
    #expect(binary.leadingArguments.isEmpty)
    #expect(binary.command.hasSuffix("/use-cases"))
    #expect(binary.command.contains("UseCasesCLI/.build/"))

    let versioned = try await binary.runJson(["version"])
    #expect(versioned.exitCode == 0)
    #expect(versioned.envelope.command == "version")
    #expect(versioned.envelope.schemaVersion == 1)
    #expect(versioned.isOk == true)
  }

  @Test
  func `UC_BIN names the binary, so the same suite can run against any build`()
    async throws
  {
    let directory = try TemporaryDirectory("harness")
    let fake = try Self.fakeBinary(directory, body: "echo '\(Self.versionEnvelope)'")

    let binary = try CliBinary.resolved(override: fake)
    #expect(binary.overridden == true)
    #expect(binary.command == fake)
    #expect(binary.leadingArguments.isEmpty)

    let versioned = try await binary.runJson(["version"])
    #expect(versioned.envelope.command == "version")
  }

  @Test
  func `a nonzero exit is returned, not thrown — refusals are behaviours under test`()
    async throws
  {
    let directory = try TemporaryDirectory("harness")
    let envelope = Self.versionEnvelope
      .replacingOccurrences(of: "\"command\":\"version\"", with: "\"command\":\"scan\"")
      .replacingOccurrences(of: "\"ok\":true", with: "\"ok\":false")
    let fake = try Self.fakeBinary(directory, body: "echo '\(envelope)'\nexit 4")

    let scanned = try await CliBinary.resolved(override: fake).runJson(["scan"])
    #expect(scanned.exitCode == 4)
    #expect(scanned.isOk == false)
  }

  @Test
  func `a UC_BIN that emits nothing parseable fails loudly, naming the command`()
    async throws
  {
    let directory = try TemporaryDirectory("harness")
    let fake = try Self.fakeBinary(directory, body: "echo 'not json' >&2\nexit 1")
    let binary = try CliBinary.resolved(override: fake)

    await #expect {
      _ = try await binary.runJson(["scan"])
    } throws: { error in
      String(describing: error)
        .contains("use-cases scan --json: stdout did not parse as JSON")
    }
  }

  @Test
  func `run hands back raw stdout for the human output path`() async throws {
    let versioned = try await CliBinary.resolved(override: nil).run(["version"])
    #expect(versioned.exitCode == 0)
    #expect(!versioned.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  /// Not in the TypeScript, and the reason the whole file exists.
  ///
  /// The TypeScript harness could not fall back silently — an unrunnable
  /// `UC_BIN` made `spawnSync` fail and the test blew up. The Swift seam
  /// resolves a path itself, so "named binary missing → use the default one"
  /// is a mistake it could actually make, and nothing else would notice.
  @Test(arguments: ["/nonexistent/use-cases", "/etc/hosts"])
  func `a UC_BIN that cannot be run is refused rather than replaced`(named: String) throws {
    #expect(throws: OracleFailure.self) {
      _ = try CliBinary.resolved(override: named)
    }
    #expect(throws: OracleFailure.self) {
      _ = try McpSession.resolvedBinary(override: named)
    }
  }
}
