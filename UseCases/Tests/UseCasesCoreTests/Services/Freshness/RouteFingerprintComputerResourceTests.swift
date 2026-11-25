import Foundation
import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerResourceTests {
  private func fixture(
    resources: [String],
    root: String = FreshnessSamples.root(),
  ) throws -> FreshnessFixture {
    try FreshnessFixture(
      root: root,
      definitions: FreshnessSamples.definitions(resources: resources),
    )
  }

  @Test
  func `an explicit resource file and a glob reach the fingerprint through the encoder`() throws {
    let fixture = try fixture(
      resources: [
        FreshnessSamples.file("config/pins.txt"),
        FreshnessSamples.glob("fixtures/*.json"),
      ],
    )
    try fixture.write("config/pins.txt", "pin\n")
    try fixture.write("fixtures/b.json", "{\"b\":1}")
    try fixture.write("fixtures/a.json", "{}")

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          resources: [
            ExpectedFingerprints.resource("fixtures/b.json", text: "{\"b\":1}"),
            ExpectedFingerprints.resource("config/pins.txt", text: "pin\n"),
            ExpectedFingerprints.resource("fixtures/a.json", text: "{}"),
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `a resource of one route does not touch the fingerprint of another`() throws {
    let with = try fixture(resources: [FreshnessSamples.file("a.json")])
    let without = try FreshnessFixture()
    try with.write("a.json", "{}")

    #expect(try with.fingerprint(of: "manual") == without.fingerprint(of: "manual"))
    #expect(try with.fingerprint() != without.fingerprint())
  }

  @Test
  func `adding a matched file changes the fingerprint`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try fixture.write("fixtures/a.json", "{}")
    let before = try fixture.fingerprint()

    try fixture.write("fixtures/b.json", "{}")

    #expect(try fixture.fingerprint() != before)
  }

  @Test
  func `removing a matched file changes the fingerprint`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try fixture.write("fixtures/a.json", "{}")
    try fixture.write("fixtures/b.json", "{}")
    let before = try fixture.fingerprint()

    try FileManager.default.removeItem(
      at: fixture.workspace.directory.location(of: "fixtures/b.json"),
    )

    #expect(try fixture.fingerprint() != before)
  }

  @Test
  func `changing a matched file changes the fingerprint`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try fixture.write("fixtures/a.json", "{}")
    let before = try fixture.fingerprint()

    try fixture.write("fixtures/a.json", "{\"changed\":true}")

    #expect(try fixture.fingerprint() != before)
  }

  @Test
  func `renaming a matched file changes the fingerprint`() throws {
    let before = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    let after = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try before.write("fixtures/a.json", "{}")
    try after.write("fixtures/b.json", "{}")

    #expect(try before.fingerprint() != after.fingerprint())
  }

  @Test
  func `a file reached by two declarations contributes once`() throws {
    let once = try fixture(resources: [FreshnessSamples.file("fixtures/a.json")])
    let twice = try fixture(
      resources: [
        FreshnessSamples.file("fixtures/a.json"),
        FreshnessSamples.glob("fixtures/*.json"),
        FreshnessSamples.glob("**/a.json"),
      ],
    )
    try once.write("fixtures/a.json", "{}")
    try twice.write("fixtures/a.json", "{}")

    #expect(try once.fingerprint() == twice.fingerprint())
  }

  @Test
  func `the glob that found the files is not part of the fingerprint`() throws {
    let explicit = try fixture(resources: [FreshnessSamples.file("fixtures/a.json")])
    let glob = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try explicit.write("fixtures/a.json", "{}")
    try glob.write("fixtures/a.json", "{}")

    #expect(try explicit.fingerprint() == glob.fingerprint())
  }

  @Test
  func `the order resources are written in does not matter`() throws {
    let forward = try fixture(
      resources: [FreshnessSamples.file("a.json"), FreshnessSamples.file("b.json")],
    )
    let backward = try fixture(
      resources: [FreshnessSamples.file("b.json"), FreshnessSamples.file("a.json")],
    )

    for fixture in [forward, backward] {
      try fixture.write("a.json", "1")
      try fixture.write("b.json", "2")
    }

    #expect(try forward.fingerprint() == backward.fingerprint())
  }

  @Test
  func `a resource file is read under the policy: line endings are ignored by default`() throws {
    let unix = try fixture(resources: [FreshnessSamples.file("a.txt")])
    let crlf = try fixture(resources: [FreshnessSamples.file("a.txt")])
    try unix.write("a.txt", "one\ntwo\n")
    try crlf.write("a.txt", "one\r\ntwo\r\n")

    #expect(try unix.fingerprint() == crlf.fingerprint())
  }

  @Test
  func `resource paths count in content-and-locator mode as they do in content mode`() throws {
    let root = FreshnessSamples.root(bindingIdentity: "content-and-locator")
    let named = try fixture(resources: [FreshnessSamples.file("a.json")], root: root)
    let renamed = try fixture(resources: [FreshnessSamples.file("b.json")], root: root)
    try named.write("a.json", "{}")
    try renamed.write("b.json", "{}")

    #expect(try named.fingerprint() != renamed.fingerprint())
  }

  @Test
  func `an explicit path may name a file in an excluded folder`() throws {
    let fixture = try fixture(
      resources: [FreshnessSamples.file("vendor/a.json")],
      root: FreshnessSamples.root(exclude: ["vendor"]),
    )
    try fixture.write("vendor/a.json", "{}")

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          resources: [ExpectedFingerprints.resource("vendor/a.json", text: "{}")],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `an excluded file never changes the fingerprint of a glob`() throws {
    let fixture = try fixture(
      resources: [FreshnessSamples.glob("**/*.json")],
      root: FreshnessSamples.root(exclude: ["vendor"]),
    )
    try fixture.write("fixtures/a.json", "{}")
    try fixture.write("vendor/a.json", "{}")
    let before = try fixture.fingerprint()

    try fixture.write("vendor/a.json", "{\"changed\":true}")
    try fixture.write("vendor/b.json", "{}")
    try fixture.write(".git/c.json", "{}")

    #expect(try fixture.fingerprint() == before)

    try fixture.write("fixtures/a.json", "{\"changed\":true}")

    #expect(try fixture.fingerprint() != before)
  }

  @Test
  func `a glob matches a symlink as the text it holds`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("links/*")])
    try fixture.workspace.directory.symlink(
      "links/current",
      to: "../releases/v1",
    )

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          resources: [ExpectedFingerprints.resource("links/current", text: "../releases/v1")],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `a hard link is a separate file: its path is its identity`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("fixtures/*.json")])
    try fixture.write("fixtures/a.json", "{}")
    try FileManager.default.linkItem(
      at: fixture.workspace.directory.location(of: "fixtures/a.json"),
      to: fixture.workspace.directory.location(of: "fixtures/b.json"),
    )

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          resources: [
            ExpectedFingerprints.resource("fixtures/a.json", text: "{}"),
            ExpectedFingerprints.resource("fixtures/b.json", text: "{}"),
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }
}
