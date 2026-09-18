//: @use-case:ci.gate.swift_packages_are_built_tested_and_gated
import Foundation
import Testing

/// The black-box oracle for ci.gate.swift_packages_are_built_tested_and_gated.
///
/// New in row 10b. `.github/workflows/swift.yml` is what keeps the Swift product
/// gated now that row 10d has deleted `pnpm -s test`, and a workflow is exactly the kind
/// of file that rots silently: it is read by GitHub and by nobody else. So the
/// same treatment `ReleaseWorkflowTests` gives the publisher, this gives the
/// gate — the file is parsed, not grepped, and the assertions are about what the
/// job actually does.
///
/// What it cannot prove is that the workflow RUNS: it has never been fired, and
/// nothing here can fire it. The runner label, the availability of `brew install
/// swiftformat swiftlint` and the whole `verify --all` step are unproven until
/// GitHub runs this file for the first time.
struct CiWorkflowTests {
  static let path = "\(OracleLayout.repositoryRoot)/.github/workflows/swift.yml"

  static func source() throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
  }

  static func workflow() throws -> OracleYaml {
    try OracleYaml.parse(source())
  }

  /// The one job's steps, as the shell text each one runs (a `uses:` step
  /// contributes its action name, so a step list can be searched uniformly).
  static func steps() throws -> [String] {
    let job = try #require(try workflow()["jobs"]?["swift"])
    let steps = try #require(job["steps"]?.sequenceValue)
    return steps.map { step in
      [step["name"]?.stringValue, step["uses"]?.stringValue, step["run"]?.stringValue]
        .compactMap { part in
          part
        }
        .joined(separator: "\n")
    }
  }

  @Test
  func `the gate fires on every push and pull request and runs on macOS`() throws {
    let workflow = try Self.workflow()
    let triggers = try #require(workflow["on"], "the workflow declares no triggers")
    // The same two triggers ci.yml carries, so the Swift gate runs everywhere
    // the TypeScript gate runs today and 10d removes a like for like.
    #expect(triggers.sortedKeys == ["pull_request", "push"])

    let jobs = try #require(workflow["jobs"]?.mappingValue)
    #expect(!jobs.isEmpty)
    for (name, job) in jobs {
      #expect(
        job["runs-on"]?.stringValue?.hasPrefix("macos-") == true,
        Comment(rawValue: "\(name): the oracle drives real binaries, so the gate is macOS"),
      )
    }
  }

  @Test
  func `all four packages are built and tested`() throws {
    let source = try Self.source()
    for package in ["UseCasesCore", "UseCasesCLI", "UseCasesMCP"] {
      #expect(
        source.contains("swift build --package-path \"$package\"")
          || source.contains("swift build --package-path \(package)"),
        Comment(rawValue: "\(package) must be built"),
      )
    }
    // The three products are looped over by name; the oracle is its own step
    // because it needs the binaries the others produced.
    let looped = try #require(
      Self.steps().first { step in
        step.contains("swift test --package-path \"$package\"")
      },
    )
    for package in ["UseCasesCore", "UseCasesCLI", "UseCasesMCP"] {
      #expect(looped.contains(package), Comment(rawValue: "\(package) must be tested"))
    }
    #expect(source.contains("swift test --package-path UseCasesOracle"))
  }

  @Test
  func `the oracle is pointed at the binaries this job built, and refuses a missing one`() throws {
    let step = try #require(
      Self.steps().first { step in
        step.contains("swift test --package-path UseCasesOracle")
      },
    )
    // The seam the TypeScript oracle used, named explicitly rather than left to
    // the default resolution — in CI the default would still find the build, but
    // an explicit UC_BIN is what makes the step say which binary it proved.
    #expect(step.contains("UC_BIN="))
    #expect(step.contains("UC_MCP_BIN="))
    #expect(step.contains("--show-bin-path"))
    #expect(step.contains("export UC_BIN UC_MCP_BIN"))
    // A binary that is missing or not executable stops the step rather than
    // letting the suite fall back to another one.
    #expect(step.contains("test -x \"$UC_BIN\""))
    #expect(step.contains("test -x \"$UC_MCP_BIN\""))
  }

  @Test
  func `both lint gates run strictly and prove they read files`() throws {
    let steps = try Self.steps()
    let format = try #require(
      steps.first { step in
        step.contains("swiftformat --lint")
      },
    )
    let lint = try #require(
      steps.first { step in
        step.contains("swiftlint lint --strict")
      },
    )
    // A package missing from .swiftlint.yml's `included:` lints zero files and
    // reports zero violations. Each gate therefore has to show it read
    // something, or it is a pass that proves nothing.
    #expect(format.contains("files"))
    #expect(format.contains("proved nothing"))
    #expect(lint.contains("in [1-9][0-9]* files"))
    #expect(lint.contains("proved nothing"))
  }

  @Test
  func `the runner's architecture is asserted, not assumed from the label`() throws {
    let step = try #require(
      Self.steps().first { step in
        step.contains("uname -m") && step.contains("arm64")
      },
    )
    // Every bootstrap suite is gated on Apple Silicon, so a runner that is not
    // arm64 would skip them all and pass. The job refuses instead.
    #expect(step.contains("exit 1"))
    #expect(step.contains("release.distribution"))
  }

  @Test
  func `the matrix is gated by the Swift binary this job built`() throws {
    let step = try #require(
      Self.steps().first { step in
        step.contains("verify --repo . --all")
      },
    )
    #expect(step.contains("scan --repo . --gate"))
    // The mode is what decides the bar, so it is stated rather than inherited:
    // release mode needs signed proofs, which only use-cases.yml's prove job
    // mints, and this gate never sees that key.
    #expect(step.contains("--policy-mode feature"))
    // The build under test, not the plugin wrapper and not the Node bundle: a
    // gate run through `bin/use-cases` would be proving whatever that resolves
    // to, which today is the committed bundle.
    #expect(step.contains("--show-bin-path"))
    #expect(!step.contains("bin/use-cases "))
    #expect(!step.contains("node "))
  }

  @Test
  func `the Swift gate is its own workflow and leaves the existing gates alone`() throws {
    let source = try Self.source()

    #expect(FileManager.default.fileExists(atPath: Self.path))
    // The half of this test that read ci.yml went with ci.yml: ADR 0007 row 10d
    // deleted the TypeScript and the workflow that gated it, so this IS the
    // build-and-test gate now. Its surviving purpose stands unchanged — the
    // gate publishes nothing, because releases are release.yml's job alone.
    #expect(!source.contains("gh release"))
    #expect(!source.contains("SHA256SUMS"))
    // And the toolchain it deleted has not crept back in through the gate. The
    // parsed STEPS, not the file text: the header comment explains what was
    // removed and naming it there is the point.
    for step in try Self.steps() {
      #expect(!step.contains("pnpm"), Comment(rawValue: step))
      #expect(!step.contains("vitest"), Comment(rawValue: step))
    }
  }
}

//: @use-case:end ci.gate.swift_packages_are_built_tested_and_gated
