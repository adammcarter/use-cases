import Testing
@testable import UseCasesCore

struct FileContentReaderTests {
  private let directory: TemporaryDirectory
  private let context: DiscoveryContext
  private let reader = FileContentReader(fileSystem: LocalFileSystem())

  init() throws {
    directory = try TemporaryDirectory()
    context = DiscoveryContext(
      rootDirectory: directory.url,
      builtInExcludes: [],
      configuredExcludes: [],
    )
  }

  private func read(_ path: String) throws(FileContentError) -> [UInt8] {
    try reader.bytes(
      of: workspacePathOrRoot(path),
      in: context,
    )
  }

  private func workspacePathOrRoot(_ text: String) -> WorkspacePath {
    (try? WorkspacePath(validating: text)) ?? .root
  }

  @Test
  func `it reads a file exactly as stored`() throws {
    let stored: [UInt8] = [0xEF, 0xBB, 0xBF, 0x61, 0x0D, 0x0A, 0xFF]
    try directory.write("a.bin", bytes: stored)

    #expect(try read("a.bin") == stored)
  }

  @Test
  func `a symlink reads as the text it points with, not what is there`() throws {
    try directory.write("target.txt", "hello")
    try directory.symlink("link", to: "target.txt")

    #expect(try read("link") == Array("target.txt".utf8))
  }

  @Test
  func `a dangling symlink still reads as its text`() throws {
    try directory.symlink("link", to: "nowhere")

    #expect(try read("link") == Array("nowhere".utf8))
  }

  @Test
  func `nothing there is missing`() throws {
    #expect(throws: FileContentError.missing) {
      try read("nope.txt")
    }
  }

  @Test
  func `a folder is not a file`() throws {
    try directory.makeDirectory("folder")

    #expect(throws: FileContentError.notAFile(.directory)) {
      try read("folder")
    }
  }

  @Test
  func `a pipe is never opened`() throws {
    try directory.makeFIFO("pipe")

    #expect(throws: FileContentError.notAFile(.other)) {
      try read("pipe")
    }
  }
}
