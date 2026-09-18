import Foundation
import Testing

//: @use-case:release.distribution.failed_download_says_what_to_do
/// The black-box oracle for release.distribution.failed_download_says_what_to_do —
/// the Swift shape of `tests/plugin/bootstrap-failures.test.ts`.
///
/// Every refusal path of `bin/use-cases-bootstrap`, each asserted on the message
/// the user actually gets and on the cache staying empty. Apple-Silicon-gated
/// like the other bootstrap suites.
struct BootstrapFailuresTests {
  static let refusedBaseUrl = "http://127.0.0.1:1/downloads"

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `an asset the release does not carry names the asset, the release and the URL`(
  ) async throws {
    var options = ReleaseStandIn.Options()
    options.omitArchive = true
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
    #expect(result.standardError.contains(release.assetName))
    #expect(result.standardError.contains("v\(release.version)"))
    #expect(
      result.standardError
        .contains("\(release.baseUrl)/v\(release.version)/\(release.assetName)"),
    )
    #expect(result.standardError.contains("does not carry"))
    // bin/use-cases now runs whatever the resolver picks, so the escape hatch a
    // failed download names is the committed bundle itself, by its path.
    let bundle = "\(OracleLayout.repositoryRoot)/dist/uc.js"
    #expect(result.standardError.contains(bundle))
    #expect(
      FileManager.default.fileExists(atPath: bundle),
      "the hint must name a path that exists",
    )
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a host that refuses connections is reported as a download failure, not a checksum one`()
    async throws
  {
    let cache = try TemporaryDirectory("cache")

    let result = try await ReleaseStandIn.run(
      environment: [
        "USE_CASES_VERSION": "9.9.9-standin",
        "USE_CASES_RELEASE_BASE_URL": Self.refusedBaseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode != 0)
    #expect(result.standardError.contains("could not reach"))
    #expect(result.standardError.contains(Self.refusedBaseUrl))
    #expect(!result.standardError.contains("checksum mismatch"))
    #expect(!result.standardError.contains("does not carry"))
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a release with no SHA256SUMS is refused with its own message`() async throws {
    var options = ReleaseStandIn.Options()
    options.omitSums = true
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
    #expect(result.standardError.contains("SHA256SUMS"))
    #expect(result.standardError.contains("published no checksums"))
    #expect(result.standardError.contains("unverified"))
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a SHA256SUMS that does not list the asset is refused before the archive is trusted`()
    async throws
  {
    var options = ReleaseStandIn.Options()
    options.omitSumsLine = true
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
    #expect(
      result.standardError.contains("does not list") || result.standardError
        .contains("do not list"),
    )
    #expect(result.standardError.contains(release.assetName))
    #expect(result.standardError.contains("unverified"))
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  /// An Intel Mac and a machine that is not a Mac at all. Apple Silicon is the
  /// only published platform, so BOTH are unsupported — and an Intel Mac must be
  /// told so rather than handed an arm64 binary.
  ///
  /// The TypeScript loops inside one test; per house style the loop is the
  /// parameterisation, so this is one `@Test` reporting two cases.
  @Test(
    .enabled(if: ReleaseStandIn.canRunBootstrap),
    arguments: [("Darwin", "x86_64"), ("Linux", "aarch64")],
  )
  func `an unsupported machine is named and refused before any request`(
    system: String,
    machine: String,
  ) async throws {
    let cache = try TemporaryDirectory("cache")
    let stub = try ReleaseStandIn.unameStub(system: system, machine: machine)

    let result = try await ReleaseStandIn.run(
      environment: [
        "USE_CASES_VERSION": "9.9.9-standin",
        // A URL that would fail noisily if it were ever read.
        "USE_CASES_RELEASE_BASE_URL": Self.refusedBaseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
      pathPrefix: stub.path,
    )

    #expect(result.exitCode != 0, Comment(rawValue: "\(system)/\(machine)"))
    #expect(result.standardError.contains("no published binary"))
    #expect(result.standardError.contains(system))
    #expect(result.standardError.contains(machine))
    // The published list is named, and it is Apple Silicon only.
    #expect(result.standardError.contains("macos-arm64"))
    #expect(!result.standardError.contains("macos-x86_64"))
    // The platform refusal, not a network error: nothing was fetched.
    #expect(!result.standardError.contains("could not reach"))
    #expect(ReleaseStandIn.fileTree(cache.path).isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `an archive that does not contain the requested executable is refused`() async throws {
    var options = ReleaseStandIn.Options()
    options.omitExecutable = "use-cases"
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
    #expect(result.standardError.contains(release.assetName))
    #expect(result.standardError.contains("use-cases"))
    #expect(result.standardOutput.isEmpty)
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `an unknown executable name is refused by the bootstrap itself`() async throws {
    let result = try await ReleaseStandIn.run(entry: .bootstrap, arguments: ["uc-legacy"])
    #expect(result.exitCode != 0)
    #expect(result.standardError.contains("uc-legacy"))
    #expect(result.standardError.contains("use-cases-mcp"))
  }
}

//: @use-case:end release.distribution.failed_download_says_what_to_do
