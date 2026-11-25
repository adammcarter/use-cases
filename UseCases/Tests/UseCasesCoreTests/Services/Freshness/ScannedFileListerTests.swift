import Testing
@testable import UseCasesCore

struct ScannedFileListerTests {
  private let fixture: FreshnessFixture

  init() throws {
    fixture = try FreshnessFixture(root: FreshnessSamples.root(exclude: ["vendor"]))
  }

  private func listed(using fileSystem: any FileSystemReading = LocalFileSystem()) throws
    -> ScannedFiles
  {
    let workspace = try fixture.workspace.loaded()

    return ScannedFileLister(fileSystem: fileSystem).files(
      in: workspace,
      excluding: workspace.discoveryContext,
    )
  }

  private func names(_ scanned: ScannedFiles) -> [String] {
    scanned.files.map(\.text)
  }

  @Test
  func `it lists the files the scan reads, sorted by path`() throws {
    try fixture.write("src/b.swift")
    try fixture.write("src/a.swift")
    try fixture.write("README.md")
    try fixture.write("Zed.txt")

    let scanned = try listed()

    #expect(names(scanned) == ["README.md", "Zed.txt", "src/a.swift", "src/b.swift"])
    #expect(scanned.diagnostics.isEmpty)
  }

  @Test
  func `it leaves out what discovery excludes and what Use Cases owns`() throws {
    try fixture.write("vendor/a.json")
    try fixture.write(".git/HEAD")
    try fixture.write(".use-cases/store.json")
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n")
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")
    try fixture.write("kept.txt")

    #expect(try names(listed()) == ["kept.txt"])
  }

  @Test
  func `it never enters a nested workspace`() throws {
    try fixture.write("nested/use-cases.yml", "schema_version: 1\nroot: true\n")
    try fixture.write("nested/deep/a.json")
    try fixture.write("kept.txt")

    #expect(try names(listed()) == ["kept.txt"])
  }

  @Test
  func `a symlink is a file, a folder is not, and a pipe is skipped`() throws {
    try fixture.write("real/a.txt")
    try fixture.workspace.directory.symlink("link", to: "real/a.txt")
    try fixture.workspace.directory.symlink("folder-link", to: "real")
    try fixture.workspace.directory.makeFIFO("pipe")

    #expect(try names(listed()) == ["folder-link", "link", "real/a.txt"])
  }

  @Test
  func `the order a file system lists names in does not change the answer`() throws {
    for name in ["c", "a", "b"] {
      try fixture.write("src/\(name).swift")
      try fixture.write("\(name).txt")
    }

    #expect(try listed() == listed(using: ReversedListingFileSystem()))
  }
}
