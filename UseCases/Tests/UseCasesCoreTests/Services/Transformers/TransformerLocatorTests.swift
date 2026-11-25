import Foundation
import Testing
@testable import UseCasesCore

struct TransformerLocatorTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func locator(executable: URL?) -> TransformerLocator {
    TransformerLocator(
      executable: StubExecutable(location: executable),
      fileSystem: LocalFileSystem(),
    )
  }

  private func path(_ text: String) throws -> TransformerReference {
    try .program(WorkspacePath(validating: text))
  }

  @Test
  func `a program path is the project's own file, from the workspace root`() throws {
    let found = try locator(executable: nil).command(
      for: path("tools/links"),
      in: directory.url,
    )

    #expect(found == ["\(directory.url.path)/tools/links"])
  }

  @Test
  func `a bundled name is the one program beside use-cases, which takes the name first`() throws {
    try directory.writeProgram("bin/use-cases-transformers", "exit 0\n")
    try directory.write("bin/use-cases")

    let found = try locator(executable: directory.location(of: "bin/use-cases")).command(
      for: .bundled("junit"),
      in: directory.url,
    )

    #expect(found == ["\(directory.url.path)/bin/use-cases-transformers", "junit"])
  }

  @Test
  func `the folder is found by the real path of use-cases, not by where it was linked`() throws {
    try directory.writeProgram("real/use-cases-transformers", "exit 0\n")
    try directory.write("real/use-cases")
    try directory.symlink("elsewhere/use-cases", to: directory.location(of: "real/use-cases").path)

    let found = try locator(executable: directory.location(of: "elsewhere/use-cases")).command(
      for: .bundled("junit"),
      in: directory.url,
    )

    #expect(found == ["\(directory.url.path)/real/use-cases-transformers", "junit"])
  }

  @Test
  func `a program that is a symlink is taken, as an install may link it`() throws {
    try directory.writeProgram("store/use-cases-transformers", "exit 0\n")
    try directory.write("bin/use-cases")
    try directory.symlink(
      "bin/use-cases-transformers",
      to: directory.location(of: "store/use-cases-transformers").path,
    )

    let found = try locator(executable: directory.location(of: "bin/use-cases")).command(
      for: .bundled("cargo-test"),
      in: directory.url,
    )

    #expect(found.last == "cargo-test")
  }

  @Test
  func `a program that is not beside use-cases is a clear error naming where it looked`() throws {
    try directory.write("bin/use-cases")

    #expect(
      throws: TransformerError.programMissing(
        name: "junit",
        expectedAt: "\(directory.url.path)/bin/use-cases-transformers",
      ),
    ) {
      try locator(executable: directory.location(of: "bin/use-cases")).command(
        for: .bundled("junit"),
        in: directory.url,
      )
    }
  }

  @Test
  func `a folder with that name is no program`() throws {
    try directory.write("bin/use-cases")
    try directory.makeDirectory("bin/use-cases-transformers")

    #expect(throws: TransformerError.self) {
      try locator(executable: directory.location(of: "bin/use-cases")).command(
        for: .bundled("junit"),
        in: directory.url,
      )
    }
  }

  @Test
  func `when the system cannot say where use-cases is, the error names the program`() {
    #expect(
      throws: TransformerError.programMissing(
        name: "junit",
        expectedAt: "use-cases-transformers",
      ),
    ) {
      try locator(executable: nil).command(
        for: .bundled("junit"),
        in: directory.url,
      )
    }
  }
}
