import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct BridgeSettingsCheckerPathTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.directory.makeDirectory("scripts")
    try fixture.write("tools/tool", "#!/bin/sh\n")
  }

  private func problems(
    working directory: String? = nil,
    transformer: String = "junit",
    through fileSystem: (any FileSystemReading)? = nil,
  ) throws -> [String] {
    var lines: [String] = []

    if let directory {
      lines.append("working_dir: \(directory.debugDescription)")
    }

    try fixture.write(
      "use-cases-bridge.yml",
      BridgeFileSamples.validation(
        lines: lines,
        transformer: transformer,
      ),
    )

    guard let fileSystem else {
      return fixture.problems()
    }

    do {
      _ = try fixture.load(using: .reading(through: fileSystem))
      return []
    } catch {
      return error.message.split(separator: "\n").map(String.init)
    }
  }

  // MARK: - Spelling (chapter 04 "Path spelling")

  @Test
  func `a working_dir spelled in another case than the folder is refused, naming the disk's`(
  ) throws {
    try fixture.directory.makeDirectory("Sources")

    let found = try problems(working: "SOURCES")

    #expect(found.count == 1)
    #expect(found.first?.contains("'SOURCES' is 'Sources'") == true)
    #expect(found.first?.contains("validations/0/working_dir") == true)
  }

  @Test
  func `a folder below another is spelled exactly all the way down`() throws {
    try fixture.directory.makeDirectory("Packages/Auth")

    let found = try problems(working: "Packages/auth")

    #expect(found.first?.contains("'auth' is 'Auth'") == true)
  }

  @Test
  func `a working_dir in another Unicode form than the folder is refused`() throws {
    // Made by its bytes: Foundation would write the name in decomposed form.
    let made = try fixture.directory.makeDirectory(
      namedByBytes: Array("caf\u{E9}".utf8),
      in: ".",
    )
    try #require(made)

    let found = try problems(working: "cafe\u{301}")

    #expect(found.count == 1)
    #expect(found.first?.contains("is spelled differently on disk") == true)
  }

  @Test
  func `a transformer program spelled in another case than the file is refused, naming the disk's`(
  ) throws {
    let found = try problems(transformer: "tools/TOOL")

    #expect(found.count == 1)
    #expect(found.first?.contains("'TOOL' is 'tool'") == true)
    #expect(found.first?.contains("validations/0/transformer") == true)
  }

  @Test
  func `the exact spelling is taken`() throws {
    try fixture.directory.makeDirectory("Sources")

    #expect(try problems(working: "Sources", transformer: "tools/tool").isEmpty)
  }

  // MARK: - The results store

  @Test(arguments: [".use-cases", ".USE-CASES", ".Use-Cases/runs"])
  func `the results store is no working_dir, in any spelling, there or not`(
    directory: String,
  ) throws {
    let found = try problems(working: directory)

    #expect(found.mentions("validations/0/working_dir"))
  }

  @Test(arguments: [".USE-CASES", ".Use-Cases/runs"])
  func `the store is refused by name even when it exists and the file system folds case`(
    directory: String,
  ) throws {
    try fixture.directory.makeDirectory(".use-cases/runs")

    let found = try problems(working: directory)

    #expect(found.mentions("the results store"))
  }

  // MARK: - Symlinks (chapter 04 "Symlinks")

  @Test
  func `a symlink on the way to a working_dir is refused, so the store cannot be reached by one`(
  ) throws {
    try fixture.directory.makeDirectory(".use-cases/runs")
    try fixture.directory.symlink("s", to: ".use-cases")

    let found = try problems(working: "s/runs")

    #expect(found.count == 1)
    #expect(found.first?.contains("passes through 's', a symlink, which is never followed") == true)
  }

  @Test
  func `a symlink to a folder inside the workspace is no working_dir either`() throws {
    try fixture.directory.symlink("link", to: "scripts")

    let found = try problems(working: "link")

    #expect(found.first?.contains("is a symlink, which is never followed") == true)
  }

  @Test
  func `a symlink on the way to a transformer program is refused`() throws {
    try fixture.directory.symlink("shortcut", to: "tools")

    let found = try problems(transformer: "shortcut/tool")

    #expect(found.first?.contains("passes through 'shortcut', a symlink") == true)
  }

  // MARK: - Where the system says a path leads

  @Test
  func `a working_dir that resolves into the results store is refused`() throws {
    let root = fixture.directory.url
    let store = root.appendingPathComponent(".use-cases/runs")
    let scripts = root.appendingPathComponent("scripts")

    let found = try problems(
      working: "scripts",
      through: CanonicalOverridingFileSystem(leads: [scripts.path: store]),
    )

    #expect(found.first?.contains("is inside the results store") == true)
  }

  @Test
  func `a working_dir that resolves out of the workspace is refused`() throws {
    let root = fixture.directory.url
    let scripts = root.appendingPathComponent("scripts")
    let outside = root.deletingLastPathComponent()

    let found = try problems(
      working: "scripts",
      through: CanonicalOverridingFileSystem(leads: [scripts.path: outside]),
    )

    #expect(found.first?.contains("is outside the workspace") == true)
  }

  @Test
  func `a working_dir that resolves to a sibling of the workspace by name is outside it`() throws {
    let root = fixture.directory.url
    let scripts = root.appendingPathComponent("scripts")
    let sibling = URL(fileURLWithPath: root.path + "-other/scripts")

    let found = try problems(
      working: "scripts",
      through: CanonicalOverridingFileSystem(leads: [scripts.path: sibling]),
    )

    #expect(found.first?.contains("is outside the workspace") == true)
  }

  @Test
  func `a transformer program that resolves out of the workspace is refused`() throws {
    let root = fixture.directory.url
    let tool = root.appendingPathComponent("tools/tool")
    let outside = root.deletingLastPathComponent().appendingPathComponent("tool")

    let found = try problems(
      transformer: "tools/tool",
      through: CanonicalOverridingFileSystem(leads: [tool.path: outside]),
    )

    #expect(found.first?.contains("is outside the workspace") == true)
  }

  // MARK: - A program is a file

  @Test
  func `a transformer program that is a folder is refused`() throws {
    try fixture.directory.makeDirectory("tools/folder")

    let found = try problems(transformer: "tools/folder")

    #expect(found.count == 1)
    #expect(found.first?.contains("transformer program 'tools/folder' is not a file") == true)
  }

  @Test
  func `a transformer program that is a symlink to a file inside is launched where it leads`(
  ) throws {
    try fixture.directory.symlink("tools/alias", to: "tool")

    #expect(try problems(transformer: "tools/alias").isEmpty)
  }

  @Test
  func `a transformer program that is a symlink to a folder or to nothing is refused`() throws {
    try fixture.directory.symlink("tools/to-folder", to: "../scripts")
    try fixture.directory.symlink("tools/dangling", to: "nowhere")

    #expect(try problems(transformer: "tools/to-folder").mentions("is not a file"))
    #expect(try problems(transformer: "tools/dangling").mentions("is not a file"))
  }
}
