import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceDiscovererDefinitionsTests {
  @Test
  func `every yml and yaml file below the use_cases_dir is a definition, recursively, sorted`(
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/z.yml")
    try fixture.directory.write("use-cases/a.yaml")
    try fixture.directory.write("use-cases/payments/card.yml")
    try fixture.directory.write("use-cases/payments/deep/er/wallet.yaml")
    try fixture.directory.write("use-cases/B.yml")

    let discovery = try fixture.discover()

    #expect(
      discovery.definitionTexts["."] == [
        "use-cases/B.yml", "use-cases/a.yaml", "use-cases/payments/card.yml",
        "use-cases/payments/deep/er/wallet.yaml", "use-cases/z.yml",
      ],
    )
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `files that are not YAML are ignored`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/real.yml")

    for name in ["notes.txt", "README", "real.yml.bak", "x.json", "x.yml~", ".DS_Store", "yml"] {
      try fixture.directory.write("use-cases/\(name)")
    }

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/real.yml"])
    #expect(discovery.diagnostics.isEmpty)
  }

  @Test
  func `a folder whose name ends yml is searched, not read as a file`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/odd.yml/inner.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/odd.yml/inner.yml"])
  }

  @Test
  func `files outside the use_cases_dir are not definitions`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("other/a.yml")
    try fixture.directory.write("a.yml")
    try fixture.directory.write("use-cases-extra/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
  }

  @Test
  func `a use_cases_dir that does not exist reads as empty, with no problem`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pay", "use_cases_dir: specs/deeper\n")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts == [".": [], "pay": []])
    #expect(discovery.diagnostics.isEmpty)
    #expect(discovery.isValid)
  }

  @Test
  func `an empty use_cases_dir gives the same answer as a missing one`() throws {
    let missing = try DiscoveryFixture()
    let empty = try DiscoveryFixture()
    try empty.directory.makeDirectory("use-cases")

    #expect(try missing.discover() == empty.discover())
  }

  @Test
  func `a use_cases_dir below the scope folder is where its definitions are`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pay", "use_cases_dir: specs/uc\n")
    try fixture.directory.write("pay/specs/uc/card.yml")
    try fixture.directory.write("pay/specs/other.yml")
    try fixture.directory.write("pay/use-cases/ignored.yml")
    try fixture.directory.write("use-cases/root.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["pay"] == ["pay/specs/uc/card.yml"])
    #expect(discovery.definitionTexts["."] == ["use-cases/root.yml"])
  }

  @Test(arguments: ["ui.YML", "ui.Yaml", "ui.yAML", "ui.YAML", "ui.yMl", "sub/ui.YML"])
  func `an ending in another casing is invalid, never read and never skipped`(name: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("use-cases/\(name)")
    try fixture.directory.write("use-cases/fine.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/fine.yml"])
    #expect(discovery.diagnostics.count == 1)
    #expect(!discovery.isValid)

    let diagnostic = try #require(discovery.diagnostics.first)
    let renamed = name.replacingOccurrences(of: "YML", with: "yml")
      .replacingOccurrences(of: "Yaml", with: "yaml")
      .replacingOccurrences(of: "yAML", with: "yaml")
      .replacingOccurrences(of: "YAML", with: "yaml")
      .replacingOccurrences(of: "yMl", with: "yml")
    let leaf = try #require(renamed.split(separator: "/").last)

    #expect(diagnostic.file.text == "use-cases/\(name)")
    #expect(diagnostic.code.text == "definition-ending-not-lower-case")
    #expect(diagnostic.message.contains("rename it to '\(leaf)'"))
    #expect(diagnostic.description.hasPrefix("use-cases/\(name): "))
  }

  @Test
  func `a symlink to a file inside a use_cases_dir is invalid and the message names it`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("shared/real.yml")
    try fixture.directory.symlink("use-cases/linked.yml", to: "../shared/real.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases/linked.yml: symlink-in-definitions"])
    #expect(discovery.diagnostics.first?.message.contains("'use-cases/linked.yml'") == true)
    #expect(!discovery.isValid)
  }

  @Test(arguments: ["dangling.yml", "to-folder", "plain-name", "up.yaml"])
  func `any kind of symlink inside a use_cases_dir is invalid`(name: String) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.makeDirectory("shared")
    try fixture.directory.makeDirectory("use-cases")
    let target = name == "to-folder" ? "../shared" : "../missing"
    try fixture.directory.symlink("use-cases/sub/\(name)", to: target)

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["use-cases/sub/\(name): symlink-in-definitions"])
  }

  @Test
  func `a folder symlink in a use_cases_dir is not entered`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("shared/inside.yml")
    try fixture.directory.symlink("use-cases/linked", to: "../shared")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
  }

  @Test(
    arguments: [
      ("build/uc", "build/**"),
      ("build/uc", "build"),
      ("build/uc", "**/uc"),
      (".git/uc", ""),
      ("x/.hg/uc", ""),
    ],
  )
  func `a use_cases_dir inside an excluded tree is invalid and says it is excluded`(
    directory: String,
    exclude: String,
  ) throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nuse_cases_dir: \(directory)\nexclude: \(exclude)\n",
    )
    try fixture.directory.write("\(directory)/a.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-excluded"])
    #expect(discovery.diagnostics.first?.message.contains("'\(directory)'") == true)
    #expect(discovery.diagnostics.first?.message.contains("excluded") == true)
  }

  @Test
  func `a symlinked use_cases_dir is invalid and never entered`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("elsewhere/a.yml")
    try fixture.directory.symlink("use-cases", to: "elsewhere")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-behind-symlink"])
    #expect(discovery.diagnostics.first?.message.contains("'use-cases'") == true)
    #expect(!discovery.isValid)
  }

  @Test
  func `a dangling symlink as the use_cases_dir is invalid too`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.symlink("use-cases", to: "nowhere")

    let discovery = try fixture.discover()

    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-behind-symlink"])
  }

  @Test
  func `a use_cases_dir behind a symlinked folder part-way along is invalid`() throws {
    let fixture = try DiscoveryFixture(rootConfiguration: "root: true\nuse_cases_dir: docs/uc\n")
    try fixture.directory.write("elsewhere/uc/a.yml")
    try fixture.directory.symlink("docs", to: "elsewhere")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-behind-symlink"])
    #expect(discovery.diagnostics.first?.message.contains("'docs'") == true)
    #expect(discovery.diagnostics.first?.message.contains("'docs/uc'") == true)
  }

  @Test(arguments: ["use-cases", "docs/use-cases"])
  func `a use_cases_dir that is a file, or sits under one, is invalid`(directory: String) throws {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nuse_cases_dir: \(directory)\n",
    )
    try fixture.directory.write(directory.split(separator: "/").first.map(String.init) ?? "")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == [])
    #expect(discovery.diagnosticSummaries == ["use-cases.yml: definitions-not-a-folder"])
    #expect(!discovery.isValid)
  }

  @Test(.enabled(if: getuid() != 0, "an administrator can list any folder"))
  func `a use_cases_dir that cannot be listed is reported and other scopes still load`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pay")
    try fixture.directory.write("use-cases/a.yml")
    try fixture.directory.write("pay/use-cases/b.yml")
    let locked = fixture.directory.location(of: "use-cases")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: locked.path,
      )
    }

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts == [".": [], "pay": ["pay/use-cases/b.yml"]])
    #expect(discovery.diagnosticSummaries == ["use-cases: unreadable-directory"])
  }

  @Test
  func `a nested workspace inside a use_cases_dir is invalid and not entered`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("use-cases/vendored", "root: true\n")
    try fixture.directory.write("use-cases/vendored/own.yml")
    try fixture.directory.write("use-cases/mine.yml")

    let discovery = try fixture.discover()

    #expect(discovery.definitionTexts["."] == ["use-cases/mine.yml"])
    #expect(discovery.nestedWorkspaces.map(\.text) == ["use-cases/vendored"])
    #expect(
      discovery
        .diagnosticSummaries == ["use-cases/vendored/use-cases.yml: scope-inside-definitions"],
    )
    #expect(discovery.diagnostics.first?.message
      .contains("'use-cases/vendored/use-cases.yml'") == true)
  }

  @Test
  func `problems in separate places are all reported, in order, and valid files still load`(
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.scope("bad", "invalid\n")
    try fixture.scope("pay")
    try fixture.directory.write("use-cases/ok.yml")
    try fixture.directory.write("use-cases/Wrong.YML")
    try fixture.directory.write("pay/use-cases/fine.yaml")
    try fixture.directory.write("pay/use-cases/Also.Yaml")
    try fixture.directory.symlink("use-cases/link.yml", to: "ok.yml")

    let discovery = try fixture.discover()

    #expect(
      discovery.diagnosticSummaries == [
        "bad/use-cases.yml: mock-invalid",
        "pay/use-cases/Also.Yaml: definition-ending-not-lower-case",
        "use-cases/Wrong.YML: definition-ending-not-lower-case",
        "use-cases/link.yml: symlink-in-definitions",
      ],
    )
    #expect(discovery.definitionTexts["."] == ["use-cases/ok.yml"])
    #expect(discovery.definitionTexts["pay"] == ["pay/use-cases/fine.yaml"])
  }

  @Test
  func `definitions come back in the same order however the file system lists them`() throws {
    let backward = try DiscoveryFixture(fileSystem: ReversedListingFileSystem())
    let forward = try DiscoveryFixture()

    for fixture in [forward, backward] {
      for name in ["c.yml", "a/z.yaml", "a/b.yml", "B.yml", "b/c/d.yml"] {
        try fixture.directory.write("use-cases/\(name)")
      }
    }

    #expect(try forward.discover().definitionTexts == backward.discover().definitionTexts)
    #expect(
      try backward.discover().definitionTexts["."] == [
        "use-cases/B.yml", "use-cases/a/b.yml", "use-cases/a/z.yaml", "use-cases/b/c/d.yml",
        "use-cases/c.yml",
      ],
    )
  }
}
