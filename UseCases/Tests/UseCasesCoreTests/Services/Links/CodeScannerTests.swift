import Foundation
import Testing
@testable import UseCasesCore

struct CodeScannerTests {
  private let fixture: WorkspaceFixture
  private let region = LinkSamples.marked("app.toggle#render", "draw()")
  private let unpaired = "// @use-case:app.toggle#render\ndraw()\n"
  private let comment = "# @use-case:app.toggle#render\n"

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
  }

  private func scanned(
    with fileSystem: any FileSystemReading = LocalFileSystem(),
  ) throws -> CodeScan {
    let workspace = try fixture.loaded()

    return CodeScanner(
      fileSystem: fileSystem,
      markerScanner: MarkerScanner(),
    ).scan(
      workspace,
      excluding: workspace.discoveryContext,
    )
  }

  private func files(of scan: CodeScan) -> [String] {
    scan.regions.map(\.file.text).sorted()
  }

  @Test
  func `every file under the root is searched, in every folder`() throws {
    try fixture.write("src/a.swift", region)
    try fixture.write("src/deep/er/b.swift", region)
    try fixture.write("README.md", region)

    #expect(try files(of: scanned()) == ["README.md", "src/a.swift", "src/deep/er/b.swift"])
  }

  @Test(arguments: [".git/hooks/x", "sub/.git/x", ".hg/x", ".svn/x", ".bzr/x", ".jj/x"])
  func `version-control history is never searched`(path: String) throws {
    try fixture.write(path, unpaired)

    let scan = try scanned()

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `the store of Use Cases is never searched, at any depth`() throws {
    try fixture.write(".use-cases/runs/one/outputs/x/console.txt", unpaired)
    try fixture.write("sub/.use-cases/runs/x/outputs/y/console.txt", unpaired)

    let scan = try scanned()

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `discovery exclude keeps folders and files out of the search`() throws {
    let fixture = try WorkspaceFixture(
      rootConfiguration: YAMLSamples
        .root + "discovery:\n  exclude:\n    - vendor\n    - \"**/*.min.js\"\n",
    )
    try fixture.writeUseCase()
    try fixture.write("vendor/lib/copy.js", unpaired)
    try fixture.write("src/app.min.js", unpaired)
    try fixture.write("src/app.js", region)
    let workspace = try fixture.loaded()

    let scan = CodeScanner(
      fileSystem: LocalFileSystem(),
      markerScanner: MarkerScanner(),
    ).scan(
      workspace,
      excluding: workspace.discoveryContext,
    )

    #expect(files(of: scan) == ["src/app.js"])
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `the files Use Cases owns are not searched`() throws {
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n" + comment)
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n" + comment)
    try fixture.write(
      "use-cases/notes/more.yml",
      YAMLSamples.file(YAMLSamples.useCase("notes", extra: comment)),
    )
    try fixture.write("use-cases.yml", YAMLSamples.root + comment)

    let scan = try scanned()

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a definition file, a child scope's use-cases file and the root's are all left alone`()
    throws
  {
    try fixture.write("child/use-cases.yml", YAMLSamples.child(prefix: "child") + comment)
    try fixture.write(
      "child/use-cases/extra.yml",
      YAMLSamples.file(YAMLSamples.useCase("other", extra: comment)),
    )
    try fixture.write("child/code.swift", region)

    let scan = try scanned()

    #expect(files(of: scan) == ["child/code.swift"])
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a nested workspace is never entered`() throws {
    try fixture.write(
      "vendor/auth/use-cases.yml",
      "schema_version: 1\nroot: true\nprefix: auth\n",
    )
    try fixture.write("vendor/auth/src/code.swift", unpaired)
    try fixture.write("vendor/auth/deeper/more.swift", unpaired)
    try fixture.write("src/app.swift", region)

    let scan = try scanned()

    #expect(files(of: scan) == ["src/app.swift"])
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a folder symlink is not followed`() throws {
    let outside = try TemporaryDirectory()
    try outside.write("copy.js", region)
    try fixture.directory.symlink("linked", to: outside.url.path)
    try fixture.write("src/app.swift", region)

    #expect(try files(of: scanned()) == ["src/app.swift"])
  }

  @Test
  func `a file symlink is read as the text it points with, never what is there`() throws {
    try fixture.write("src/real.swift", region)
    try fixture.directory.symlink("src/alias.swift", to: "real.swift")
    try fixture.directory.symlink("src/marked.txt", to: "see @use-case:app.toggle#render")

    let scan = try scanned()

    #expect(files(of: scan) == ["src/real.swift"])
    #expect(scan.diagnostics.count == 1)
    #expect(scan.diagnostics.first?.code == .markerNeverClosed)
    #expect(scan.diagnostics.first?.file.text == "src/marked.txt")
  }

  @Test
  func `a pipe is warned about and skipped, and never opened`() throws {
    try fixture.directory.makeFIFO("src/pipe.fifo")
    try fixture.write("src/app.swift", region)

    let scan = try scanned()

    #expect(files(of: scan) == ["src/app.swift"])
    #expect(scan.diagnostics.count == 1)
    #expect(scan.diagnostics.first?.file.text == "src/pipe.fifo")
    #expect(scan.diagnostics.first?.severity == .warning)
    #expect(scan.diagnostics.first?.code == .specialFileSkipped)
  }

  @Test
  func `a file whose name holds a control character is skipped with a warning that escapes it`()
    throws
  {
    try fixture.write("src/bad\nname.js", region)
    try fixture.write("src/good.js", region)

    let scan = try scanned()
    let warning = try #require(scan.diagnostics.first)

    #expect(files(of: scan) == ["src/good.js"])
    #expect(scan.diagnostics.count == 1)
    #expect(warning.severity == .warning)
    #expect(warning.file.text == "src")
    #expect(warning.message.contains("control character"))
    #expect(warning.message.contains(#"bad\nname.js"#))
    #expect(!warning.description.contains("\n"))
  }

  @Test(.enabled(if: getuid() != 0))
  func `a file the scan cannot read is a problem that names it`() throws {
    try fixture.write("src/secret.py", "y = 2\n")
    try fixture.write("src/ok.py", region)
    let secret = fixture.directory.location(of: "src/secret.py")
    let workspace = try fixture.loaded()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: secret.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret.path)
    }

    let scan = CodeScanner(
      fileSystem: LocalFileSystem(),
      markerScanner: MarkerScanner(),
    ).scan(
      workspace,
      excluding: workspace.discoveryContext,
    )

    #expect(scan.diagnostics.map(\.severity) == [.error])
    #expect(scan.diagnostics.first?.file.text == "src/secret.py")
    #expect(scan.diagnostics.first?.code == .unreadableFile)
    #expect(files(of: scan) == ["src/ok.py"])
  }

  @Test(arguments: [false, true])
  func `a file that goes between the walk and the read is not in the workspace, not a problem`(
    isSymlink: Bool,
  ) throws {
    try fixture.write("src/ok.py", region)
    if isSymlink {
      try fixture.directory.symlink("src/gone.py", to: "ok.py")
    } else {
      try fixture.write("src/gone.py", region)
    }

    let scan = try scanned(
      with: VanishingFileSystem(vanishing: fixture.directory.location(of: "src/gone.py")),
    )

    #expect(scan.diagnostics.isEmpty)
    #expect(files(of: scan) == ["src/ok.py"])
  }

  @Test(.enabled(if: getuid() != 0))
  func `a folder the scan cannot read is a problem that names it`() throws {
    try fixture.write("src/locked/inner.py", "x = 1\n")
    let locked = fixture.directory.location(of: "src/locked")
    let workspace = try fixture.loaded()
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    let scan = CodeScanner(
      fileSystem: LocalFileSystem(),
      markerScanner: MarkerScanner(),
    ).scan(
      workspace,
      excluding: workspace.discoveryContext,
    )

    #expect(scan.diagnostics.map(\.severity) == [.error])
    #expect(scan.diagnostics.first?.file.text == "src/locked")
  }

  @Test
  func `what the scan finds does not depend on the order a file system lists names in`() throws {
    try fixture.write("src/b.swift", region)
    try fixture.write("src/a.swift", region + unpaired)
    try fixture.write("tests/c.swift", region)

    let forward = try scanned()
    let reversed = try scanned(with: ReversedListingFileSystem())

    #expect(Set(forward.regions) == Set(reversed.regions))
    #expect(Set(forward.diagnostics) == Set(reversed.diagnostics))
  }
}
