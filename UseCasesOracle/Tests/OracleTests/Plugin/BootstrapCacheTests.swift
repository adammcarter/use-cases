import Foundation
import Testing

/// The black-box oracle for release.distribution.cached_binary_runs_without_network —
/// the Swift shape of `tests/plugin/bootstrap-cache.test.ts`.
///
/// Apple-Silicon-gated for the same reason as the other bootstrap suites: the
/// stand-in release has no asset to publish anywhere else.
struct BootstrapCacheTests {
  /// Nothing listens here, so any attempt to fetch fails immediately. Using it
  /// as the base URL is what turns "did not need the network" into "made no
  /// request".
  static let refusedBaseUrl = "http://127.0.0.1:1/downloads"

  static func cachedPath(
    _ cacheDirectory: String,
    version: String,
    executable: String = "use-cases",
  ) throws -> String {
    try "\(cacheDirectory)/bin/\(version)/\(ReleaseStandIn.hostPlatform())/\(executable)"
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `the second run succeeds against a host that refuses connections, and caches nothing new`()
    async throws
  {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")

    let first = try await ReleaseStandIn.run(
      arguments: ["one"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )
    #expect(first.exitCode == 0, Comment(rawValue: first.standardError))
    let afterFirst = ReleaseStandIn.fileTree(cache.path)

    let second = try await ReleaseStandIn.run(
      arguments: ["one"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": Self.refusedBaseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )
    #expect(second.exitCode == 0, Comment(rawValue: second.standardError))
    #expect(second.standardOutput == first.standardOutput)
    #expect(second.standardError.isEmpty)
    #expect(ReleaseStandIn.fileTree(cache.path) == afterFirst)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a cache entry that cannot be exec'd is refetched and verified rather than run`(
  ) async throws {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")
    let environment: [String: String?] = [
      "USE_CASES_VERSION": release.version,
      "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      "USE_CASES_CACHE_DIR": cache.path,
    ]

    let first = try await ReleaseStandIn.run(environment: environment)
    #expect(first.exitCode == 0, Comment(rawValue: first.standardError))
    let cached = try Self.cachedPath(cache.path, version: release.version)
    try ReleaseStandIn.setPermissions(0o644, of: cached)
    #expect(try ReleaseStandIn.permissions(of: cached) & 0o111 == 0)

    let again = try await ReleaseStandIn.run(arguments: ["two"], environment: environment)
    #expect(again.exitCode == 0, Comment(rawValue: again.standardError))
    #expect(
      again.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases args:two",
    )
    #expect(try ReleaseStandIn.permissions(of: cached) & 0o111 != 0)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `an unexecutable cache entry is not trusted when the release is unreachable either`()
    async throws
  {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")

    let first = try await ReleaseStandIn.run(
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )
    #expect(first.exitCode == 0, Comment(rawValue: first.standardError))
    try ReleaseStandIn.setPermissions(
      0o644,
      of: Self.cachedPath(cache.path, version: release.version),
    )

    let again = try await ReleaseStandIn.run(
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": Self.refusedBaseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )
    // It fails as a download failure; it never falls back to the entry it refused.
    #expect(again.exitCode != 0)
    #expect(again.standardOutput.isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `the cache hit short-circuits the download path, the SHA256SUMS fetch included`(
  ) async throws {
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")
    let environment: [String: String?] = [
      "USE_CASES_VERSION": release.version,
      "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
      "USE_CASES_CACHE_DIR": cache.path,
    ]

    let first = try await ReleaseStandIn.run(environment: environment)
    #expect(first.exitCode == 0, Comment(rawValue: first.standardError))

    // Empty the release entirely: archive and sums both gone, base URL unchanged.
    let sums = "\(release.releaseDirectory)/SHA256SUMS"
    try? FileManager.default.removeItem(atPath: "\(release.releaseDirectory)/\(release.assetName)")
    try? FileManager.default.removeItem(atPath: sums)
    #expect(!FileManager.default.fileExists(atPath: sums))

    let again = try await ReleaseStandIn.run(arguments: ["three"], environment: environment)
    #expect(again.exitCode == 0, Comment(rawValue: again.standardError))
    #expect(
      again.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases args:three",
    )
  }
}
