import Foundation
import Testing

/// The black-box oracle for release.distribution.first_run_downloads_and_verifies —
/// the Swift shape of `tests/plugin/bootstrap-first-run.test.ts`.
///
/// The subject is the real `bin/use-cases-bootstrap`, driven against a stand-in
/// release on disk. Nothing here imports the product: the bootstrap is a bash
/// script and these tests read what it did to the filesystem and to its own
/// streams.
///
/// Every test is `.enabled(if: canRunBootstrap)` — the TypeScript's
/// `describe.skipIf(!canRunBootstrap)`, moved onto each `@Test` because the
/// house style has no `@Suite` to hang it on. Apple Silicon is the only
/// published platform, so off it the stand-in has no asset to publish and these
/// rows are not provable at all.
struct BootstrapFirstRunTests {
  static func cachedPath(
    _ cacheDirectory: String,
    version: String,
    executable: String,
  ) throws -> String {
    try "\(cacheDirectory)/bin/\(version)/\(ReleaseStandIn.hostPlatform())/\(executable)"
  }

  // golden: the whole path, end to end.
  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `downloads the archive, verifies it, caches both executables and execs the one asked for`(
  )
    async throws
  {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      arguments: ["hello", "world"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(
      result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases args:hello world",
    )

    let cached = try Self.cachedPath(cache.path, version: release.version, executable: "use-cases")
    #expect(
      FileManager.default.fileExists(atPath: cached),
      Comment(rawValue: "expected the executable at \(cached)"),
    )
    #expect(try ReleaseStandIn.permissions(of: cached) & 0o111 != 0)
    // One download serves both executables the archive carries.
    #expect(
      try FileManager.default.fileExists(
        atPath: Self.cachedPath(
          cache.path,
          version: release.version,
          executable: "use-cases-mcp",
        ),
      ),
    )
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `the executable's exit code and stderr are the bootstrap's own`() async throws {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")
    let environment: [String: String?] = [
      "USE_CASES_VERSION": release.version,
      "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      "USE_CASES_CACHE_DIR": cache.path,
    ]

    let result = try await ReleaseStandIn.run(arguments: ["--fail"], environment: environment)
    #expect(result.exitCode == 3)
    #expect(result.standardError.contains("stand-in use-cases refused"))

    // The mcp wrapper reaches its own executable, not the CLI.
    let mcp = try await ReleaseStandIn.run(
      entry: .useCasesMcp,
      arguments: ["ping"],
      environment: environment,
    )
    #expect(mcp.exitCode == 0, Comment(rawValue: mcp.standardError))
    #expect(
      mcp.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases-mcp args:ping",
    )
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `an archive whose checksum does not match is refused, named and never cached`()
    async throws
  {
    var options = ReleaseStandIn.Options()
    options.corruptArchive = true
    let release = try await ReleaseStandIn.publish(options)
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode != 0)
    #expect(result.standardError.contains("checksum mismatch"))
    #expect(result.standardError.contains(release.assetName))
    #expect(result.standardError.contains(release.publishedSha256))
    #expect(result.standardError.contains(release.servedSha256))
    #expect(result.standardOutput.isEmpty)
    // Nothing unverified is left behind for the next run to pick up.
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `with no cache override the cache is per-user state under the user cache directory`()
    async throws
  {
    let release = try await ReleaseStandIn.publish()
    let home = try TemporaryDirectory("home")

    let result = try await ReleaseStandIn.run(
      environment: [
        "HOME": home.path,
        "XDG_CACHE_HOME": nil,
        "USE_CASES_CACHE_DIR": nil,
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      ],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    let cached = try "\(home.path)/Library/Caches/use-cases/bin/\(release.version)/" +
      "\(ReleaseStandIn.hostPlatform())/use-cases"
    #expect(
      FileManager.default.fileExists(atPath: cached),
      Comment(rawValue: "expected the executable at \(cached)"),
    )
    // Nothing is written into the repository or the plugin checkout.
    #expect(cached.hasPrefix(home.path))
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `XDG_CACHE_HOME moves the cache when it is set`() async throws {
    let release = try await ReleaseStandIn.publish()
    let xdg = try TemporaryDirectory("xdg")

    let result = try await ReleaseStandIn.run(
      environment: [
        "XDG_CACHE_HOME": xdg.path,
        "USE_CASES_CACHE_DIR": nil,
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      ],
    )

    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    let cached = try "\(xdg.path)/use-cases/bin/\(release.version)/" +
      "\(ReleaseStandIn.hostPlatform())/use-cases"
    #expect(FileManager.default.fileExists(atPath: cached))
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a cache directory from an earlier version is left alone`() async throws {
    var first = ReleaseStandIn.Options()
    first.version = "1.0.0-standin"
    var second = ReleaseStandIn.Options()
    second.version = "2.0.0-standin"
    let cache = try TemporaryDirectory("cache")

    for options in [first, second] {
      let release = try await ReleaseStandIn.publish(options)
      let result = try await ReleaseStandIn.run(
        environment: [
          "USE_CASES_VERSION": release.version,
          "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
          "USE_CASES_CACHE_DIR": cache.path,
        ],
      )
      #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    }

    // Keyed by version, so both live side by side and an upgrade re-downloads.
    for version in ["1.0.0-standin", "2.0.0-standin"] {
      #expect(
        try FileManager.default.fileExists(
          atPath: Self.cachedPath(cache.path, version: version, executable: "use-cases"),
        ),
        Comment(rawValue: version),
      )
    }
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a forced platform decides the asset and cache key; an unpublished one is refused`(
  )
    async throws
  {
    // A well-formed slug that no release carries: Apple Silicon is the only
    // published platform, so this is what a second platform would be tested
    // through, and what a user forcing a retired one now gets.
    let forced = ReleaseStandIn.unpublishedPlatform()
    var options = ReleaseStandIn.Options()
    options.platform = forced
    let release = try await ReleaseStandIn.publish(options)
    let cache = try TemporaryDirectory("cache")
    let environment: [String: String?] = [
      "USE_CASES_PLATFORM": forced,
      "USE_CASES_VERSION": release.version,
      "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      "USE_CASES_CACHE_DIR": cache.path,
    ]

    let result = try await ReleaseStandIn.run(arguments: ["forced"], environment: environment)
    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(
      result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases args:forced",
    )
    #expect(
      FileManager.default
        .fileExists(atPath: "\(cache.path)/bin/\(release.version)/\(forced)/use-cases"),
    )
    // Not under this machine's own slug: the force decided the cache key too.
    #expect(
      try !FileManager.default.fileExists(
        atPath: Self.cachedPath(
          cache.path,
          version: release.version,
          executable: "use-cases",
        ),
      ),
    )

    // A forced platform the release does not publish is refused at the
    // checksums — the sums are the gate — never exec'd as the wrong slice.
    let otherCache = try TemporaryDirectory("cache")
    var absentEnvironment = environment
    absentEnvironment["USE_CASES_PLATFORM"] = try ReleaseStandIn.hostPlatform()
    absentEnvironment["USE_CASES_CACHE_DIR"] = otherCache.path
    let absent = try await ReleaseStandIn.run(environment: absentEnvironment)
    #expect(absent.exitCode != 0)
    #expect(
      absent.standardError.contains("does not list")
        || absent.standardError.contains("do not list")
        || absent.standardError.contains("does not carry"),
    )
    #expect(
      try absent.standardError
        .contains("use-cases-\(release.version)-\(ReleaseStandIn.hostPlatform()).tar.gz"),
    )
    #expect(absent.standardOutput.isEmpty)
  }
}
