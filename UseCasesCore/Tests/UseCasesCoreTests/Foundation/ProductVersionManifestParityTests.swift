import Foundation
import Testing
@testable import UseCasesCore

/// The four places the product's version is written must agree, and until this
/// suite existed nothing joined them.
///
/// `ProductVersion.version` is what every CLI and MCP envelope reports.
/// `.claude-plugin/plugin.json` is what `bin/use-cases-runtime` and
/// `bin/use-cases-bootstrap` read to decide which release to download — so a
/// manifest lagging behind the binary sends a host to the wrong release, and a
/// manifest ahead of it sends one to a release that does not exist. The Codex
/// and OpenCode manifests are the same claim made to two more hosts.
///
/// ADR 0007 row 10d noted these three files can drift with nothing joining
/// them; the 0.8.0 bump of row 11 is the first time all four had to move
/// together, which is why the join is written now. CONTRIBUTING.md already
/// states the rule ("The three products stay on the same version, which is the
/// one in `.claude-plugin/plugin.json`") — this is that sentence, enforced.
struct ProductVersionManifestParityTests {
  /// Every manifest that declares the product's version, by repository path.
  static let manifestPaths = [
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
    "package.json",
  ]

  /// The `version` string of the manifest at `path`, read from the live file.
  private static func declaredVersion(inManifestAt path: String) throws -> String {
    let url = SchemaFixtures.repositoryRoot.appendingPathComponent(path)
    let text = try String(contentsOf: url, encoding: .utf8)
    let manifest = try JSONParser.parse(text)

    return try #require(manifest["version"]?.stringValue, "\(path) declares no version")
  }

  @Test(arguments: manifestPaths)
  func `each host manifest declares the version the binary reports`(path: String) throws {
    #expect(try Self.declaredVersion(inManifestAt: path) == ProductVersion.version)
  }

  @Test
  func `the host manifests agree with each other`() throws {
    let declared = try Self.manifestPaths.map { path in
      try Self.declaredVersion(inManifestAt: path)
    }

    #expect(Set(declared).count == 1, "the manifests declare \(declared)")
  }

  /// The runtime resolver branches on the manifest version against this
  /// constant, so a released version below it runs nothing at all. Pinning the
  /// pair here is what stops the bump landing in `ProductVersion` and the
  /// manifests while the plugin still refuses to run.
  @Test
  func `the published version is at or above the first Swift release`() throws {
    let url = SchemaFixtures.repositoryRoot.appendingPathComponent("bin/use-cases-runtime")
    let script = try String(contentsOf: url, encoding: .utf8)
    let pattern = #/readonly FIRST_SWIFT_RELEASE="(?<version>[^"]+)"/#
    let first = try #require(script.firstMatch(of: pattern)?.output.version)

    #expect(!Self.isBelow(ProductVersion.version, String(first)))
  }

  /// Whether `version` orders below `floor`, comparing each release number as
  /// an integer so `0.10.0` sits above `0.8.0` rather than below it the way
  /// strings do. This mirrors `at_least` in `bin/use-cases-runtime`, which
  /// compares three integers by hand for exactly that reason.
  private static func isBelow(
    _ version: String,
    _ floor: String,
  ) -> Bool {
    let have = numbers(version)
    let want = numbers(floor)
    for index in 0 ..< 3 where have[index] != want[index] {
      return have[index] < want[index]
    }
    return false
  }

  /// A semantic version's three release numbers, prerelease and build metadata
  /// dropped, short versions padded with zeroes.
  private static func numbers(_ version: String) -> [Int] {
    let core = version.split(separator: "+").first.map(String.init) ?? version
    let release = core.split(separator: "-").first.map(String.init) ?? core
    let parsed = release.split(separator: ".").map { component in
      Int(component) ?? 0
    }
    return parsed + Array(repeating: 0, count: max(0, 3 - parsed.count))
  }
}
