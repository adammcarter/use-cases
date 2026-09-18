import Foundation
import Testing

//: @use-case:release.distribution.release_publishes_checksummed_assets
/// The black-box oracle for release.distribution.release_publishes_checksummed_assets —
/// the Swift shape of `tests/plugin/release-workflow.test.ts`.
///
/// The subjects are two files that must agree and nothing else joins:
/// `.github/workflows/release.yml`, which publishes the assets, and
/// `bin/use-cases-bootstrap`, which downloads them. They agree on the asset
/// name, the platform list and the tag, or an installed plugin breaks on a
/// release nobody tested.
struct ReleaseWorkflowTests {
  static let workflowPath = "\(OracleLayout.repositoryRoot)/.github/workflows/release.yml"

  static func releaseSource() throws -> String {
    try String(contentsOfFile: workflowPath, encoding: .utf8)
  }

  static func bootstrapSource() throws -> String {
    try String(
      contentsOfFile: "\(OracleLayout.repositoryRoot)/bin/use-cases-bootstrap",
      encoding: .utf8,
    )
  }

  static func matches(
    _ pattern: String,
    in source: String,
  ) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    let range = NSRange(source.startIndex ..< source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
      Range(match.range, in: source).map { found in
        String(source[found])
      }
    }
  }

  static func platformSlugs(_ source: String) -> [String] {
    Array(Set(matches("macos-(?:arm64|x86_64)", in: source))).sorted()
  }

  /// The asset-name template, with the shell variables normalised away.
  static func assetTemplate(_ source: String) -> String? {
    let variable = "\\$\\{?[A-Za-z_][A-Za-z_0-9]*\\}?"
    guard let found = matches(
      "use-cases-\(variable)-\(variable)\\.tar\\.gz",
      in: source,
    ).first else {
      return nil
    }
    guard let regex = try? NSRegularExpression(pattern: variable) else {
      return nil
    }
    return regex.stringByReplacingMatches(
      in: found,
      range: NSRange(found.startIndex ..< found.endIndex, in: found),
      withTemplate: "\\${}",
    )
  }

  @Test
  func `the workflow builds both executables in release configuration for the published platform`()
    throws
  {
    let source = try Self.releaseSource()
    let workflow = try OracleYaml.parse(source)
    let jobs = try #require(workflow["jobs"]?.mappingValue)

    #expect(!jobs.isEmpty)
    for (name, job) in jobs {
      #expect(
        job["runs-on"]?.stringValue?.hasPrefix("macos-") == true,
        Comment(rawValue: "\(name): release assets must be built on macOS"),
      )
    }

    #expect(!Self.matches("swift build .*-c release", in: source).isEmpty)
    #expect(source.contains("--arch arm64"))
    #expect(source.contains("UseCasesCLI"))
    #expect(source.contains("UseCasesMCP"))
    // One thin arm64 build, so there is nothing to slice: lipo stays only as
    // the check that the product really is thin arm64.
    #expect(source.contains("lipo -info"))
    #expect(!source.contains("lipo -thin"))
    #expect(!source.contains("lipo -extract"))
  }

  @Test
  func `the workflow writes SHA256SUMS and attaches every archive to the release`() throws {
    let source = try Self.releaseSource()
    let workflow = try OracleYaml.parse(source)
    let jobs = try #require(workflow["jobs"]?.mappingValue)

    #expect(source.contains("SHA256SUMS"))
    #expect(source.contains("shasum -a 256"))
    #expect(!Self.matches("gh release (create|upload)", in: source).isEmpty)
    #expect(source.contains("GITHUB_TOKEN"))
    // Attaching assets needs write access, declared where the publish job
    // declares it.
    let writesContents = jobs.values.contains { job in
      job["permissions"]?["contents"]?.stringValue == "write"
    }
    #expect(writesContents, "a job must declare permissions: contents: write")
  }

  @Test
  func `the publisher and the bootstrap agree on the asset name, the platforms and the tag`(
  ) throws {
    let workflow = try Self.releaseSource()
    let bootstrap = try Self.bootstrapSource()

    let template = Self.assetTemplate(workflow)
    #expect(
      template != nil,
      "the workflow names no use-cases-<version>-<platform>.tar.gz asset",
    )
    #expect(Self.assetTemplate(bootstrap) == template)

    #expect(Self.platformSlugs(bootstrap) == Self.platformSlugs(workflow))
    #expect(Self.platformSlugs(workflow) == ReleaseStandIn.publishedPlatforms)

    // Both resolve the release by the same v-prefixed tag as every existing tag.
    #expect(!Self.matches("v\\$\\{?[A-Za-z_][A-Za-z_0-9]*\\}?", in: workflow).isEmpty)
    #expect(!Self.matches("v\\$\\{?[A-Za-z_][A-Za-z_0-9]*\\}?", in: bootstrap).isEmpty)
    #expect(bootstrap.contains("https://github.com/adammcarter/use-cases/releases/download"))
  }

  @Test
  func `the only published platform is Apple Silicon, in both files`() throws {
    let workflow = try Self.releaseSource()
    let bootstrap = try Self.bootstrapSource()

    // The owner retired the x86_64 asset for 0.8.0: the toolchain warns the
    // architecture is deprecated for the deployment target. Nothing may build,
    // slice or attach one, and the bootstrap may not offer one.
    #expect(Self.platformSlugs(workflow) == ["macos-arm64"])
    #expect(Self.platformSlugs(bootstrap) == ["macos-arm64"])
    #expect(!workflow.contains("x86_64"))
    #expect(!bootstrap.contains("x86_64"))
    #expect(ReleaseStandIn.publishedPlatforms == ["macos-arm64"])
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `the bootstrap asks for the plugin's own version by default`() async throws {
    let pluginVersion = try ReleaseStandIn.pluginVersion()
    // A local release AT the manifest's version, carrying only its checksums:
    // the bootstrap then names the asset it wanted, with no network and no
    // USE_CASES_VERSION to tell it which version that is.
    var options = ReleaseStandIn.Options()
    options.version = pluginVersion
    options.omitArchive = true
    let release = try await ReleaseStandIn.publish(options)
    let cache = try TemporaryDirectory("cache")

    // Driven at the bootstrap itself: bin/use-cases goes through the runtime
    // resolver, which sends the plugin's own version to the committed bundle
    // until a release publishes the Swift archives.
    let result = try await ReleaseStandIn.run(
      entry: .bootstrap,
      arguments: ["use-cases"],
      environment: [
        "USE_CASES_VERSION": nil,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )

    #expect(result.exitCode != 0)
    #expect(
      try result.standardError
        .contains("use-cases-\(pluginVersion)-\(ReleaseStandIn.hostPlatform()).tar.gz"),
    )
    #expect(result.standardError.contains("v\(pluginVersion)"))
  }

  @Test
  func `the workflow never fires on a push to a branch`() throws {
    let workflow = try OracleYaml.parse(Self.releaseSource())
    let triggers = try #require(workflow["on"], "the workflow declares no triggers")

    #expect(triggers.sortedKeys == ["push", "workflow_dispatch"])
    let push = try #require(triggers["push"]?.mappingValue)
    #expect(push["branches"] == nil, "a branches filter would publish releases off branch pushes")
    #expect(push["branches-ignore"] == nil)
    let tags = try #require(push["tags"]?.sequenceValue)
    #expect(!tags.isEmpty)
    for tag in tags {
      #expect(tag.stringValue?.hasPrefix("v") == true, Comment(rawValue: tag.stringValue ?? ""))
    }
  }

  /// Publishing lives in one workflow and nowhere else.
  ///
  /// It read `ci.yml` until ADR 0007 row 10d deleted that file with the
  /// TypeScript it gated. The other two workflows took its place in the
  /// assertion, which is the half that was ever load-bearing: a second file
  /// learning to cut a release is the regression, and `swift.yml` is now the
  /// gate that would be the tempting place to add one.
  @Test
  func `the release pipeline is its own workflow and leaves the existing gates alone`() throws {
    let others = try ["swift.yml", "use-cases.yml"].map { name in
      try String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/.github/workflows/\(name)",
        encoding: .utf8,
      )
    }

    #expect(FileManager.default.fileExists(atPath: Self.workflowPath))
    for other in others {
      #expect(Self.matches("gh release", in: other).isEmpty)
      #expect(!other.contains("SHA256SUMS"))
    }
  }

  @Test(.enabled(if: ReleaseStandIn.canRunBootstrap))
  func `a stand-in release laid out the way the workflow publishes one satisfies the bootstrap`()
    async throws
  {
    // The naming agreement above is text; this is the same layout end to end.
    let release = try await ReleaseStandIn.publish()
    let cache = try TemporaryDirectory("cache")
    let result = try await ReleaseStandIn.run(
      arguments: ["layout"],
      environment: [
        "USE_CASES_VERSION": release.version,
        "USE_CASES_RELEASE_BASE_URL": release.baseUrl,
        "USE_CASES_CACHE_DIR": cache.path,
      ],
    )
    #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
    #expect(
      result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        == "stand-in use-cases args:layout",
    )
  }
}

//: @use-case:end release.distribution.release_publishes_checksummed_assets
