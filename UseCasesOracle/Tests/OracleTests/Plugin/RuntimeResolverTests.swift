import Foundation
import Testing

//: @use-case:plugin.runtime.release_versions_run_the_verified_swift_binary
/// The black-box oracle for
/// plugin.runtime.release_versions_run_the_verified_swift_binary — the Swift
/// shape of the FIRST half of `tests/plugin/runtime-resolver.test.ts`.
///
/// Every host-facing entry point in `bin/` goes through `bin/use-cases-runtime`,
/// so exactly one file decides what a command actually executes. These tests
/// drive the wrappers the way a host does and read what came out the other end.
/// The branch is chosen on the VERSION, never on a failure: a version whose
/// release publishes the Swift archives downloads and verifies one. The stand-in
/// release's default version (9.9.9-standin) is above the first Swift release,
/// so these tests need no switch of their own.
///
/// The TypeScript file's SECOND half —
/// `plugin.runtime.pre_swift_versions_run_the_committed_bundle`, four tests
/// driving the committed Node bundle — was never carried, and the row was
/// RETIRED at row 10d with the bundle it described. The resolver now has one
/// branch: at or above the first Swift release it execs the bootstrap, and
/// below it, it refuses and says why.
///
/// `a version that is not a semantic version is refused` still pins
/// `bin/use-cases-runtime`'s version parsing. Row 10 says the resolver "can be
/// folded away entirely" now that the Node branch has gone; it was kept because
/// folding it away would move this refusal, and the row bound to this file,
/// onto the bootstrap — a separate change with its own proof.
struct RuntimeResolverTests {
  /// An executable that reports the pid it is running as.
  static let pidReporter: @Sendable (String) -> String = { name in
    """
    #!/bin/sh
    echo "\(name) pid:$$"

    """
  }

  // golden_every_entry_point_execs_the_downloaded_binary
  @Test(
    .enabled(if: ReleaseStandIn.canRunBootstrap),
    arguments: [
      (ReleaseStandIn.Entry.useCases, "stand-in use-cases args:one"),
      (ReleaseStandIn.Entry.useCasesMcp, "stand-in use-cases-mcp args:one"),
    ],
  )
  func `bin use-cases and bin use-cases-mcp both exec the verified executable`(
    entry: ReleaseStandIn.Entry,
    expected: String,
  ) async throws {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      entry: entry,
      arguments: ["one"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(
      result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == expected,
    )
  }

  // golden_the_mcp_entry_point_the_manifests_name_serves_a_host
  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `the MCP entry point execs through, leaving no shell holding the process`() async throws {
    var options = ReleaseStandIn.Options()
    options.executableBody = Self.pidReporter
    let release = try await ReleaseStandIn.publish(options)
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      entry: .useCasesMcp,
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    let reported = result.standardOutput
      .components(separatedBy: "use-cases-mcp pid:")
      .dropFirst()
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let pid = try #require(reported.flatMap(Int32.init), Comment(rawValue: result.standardOutput))
    // The wrapper, the resolver and the bootstrap all exec: the process the
    // host spawned IS the server, so it owns the pipes, the signals and the
    // exit code.
    #expect(pid == result.processIdentifier)
  }

  // bad_release_without_the_asset_never_falls_back
  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a release that carries no asset fails and never runs the committed bundle`() async throws {
    var options = ReleaseStandIn.Options()
    options.omitArchive = true
    let release = try await ReleaseStandIn.publish(options)
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      arguments: ["version", "--json"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode != 0)
    #expect(result.standardError.contains(release.assetName))
    #expect(result.standardError.contains("v\(release.version)"))
    // The bundle would have printed the version envelope on stdout. Nothing
    // stood in for the release that should have carried a binary.
    #expect(result.standardOutput.isEmpty)
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  // edge_a_version_that_is_not_a_version_is_refused. No download, so this one
  // runs on every machine.
  @Test
  func `a version that is not a semantic version is refused rather than guessed`() async throws {
    let result = try await ReleaseStandIn.run(
      arguments: ["version", "--json"],
      environment: ["USE_CASES_VERSION": "not-a-version"],
    )

    #expect(result.exitCode != 0)
    #expect(result.standardError.contains("not-a-version"))
    #expect(result.standardOutput.isEmpty)
  }
}

//: @use-case:end plugin.runtime.release_versions_run_the_verified_swift_binary
