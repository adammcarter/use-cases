import Foundation
import Testing
@testable import UseCasesCore

struct StoreFileAccessStreamedFileTests {
  private let directory: TemporaryDirectory
  private let access = StoreFileAccess(
    fileSystem: LocalFileSystem(),
    json: JSONReader(),
  )
  private let hasher = SHA256Hasher()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private var root: StoreFile {
    StoreFile(workspace: directory.url).appending("folder")
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a file below a folder is digested and measured, as its bytes are`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try directory.write(".use-cases/folder/a/file.bin", bytes: bytes)

    let streamed = try access.streamedFile(
      below: root,
      path: "a/file.bin",
      using: hasher,
    )

    #expect(
      streamed == StreamedFile(
        digest: hasher.sha256Hex(of: bytes),
        length: size,
      ),
    )
    #expect(try access.bytes(below: root, path: "a/file.bin") == bytes)
  }

  @Test
  func `a name that is not there on the way is no file`() throws {
    try directory.makeDirectory(".use-cases/folder/a")

    #expect(try access.streamedFile(below: root, path: "a/nothing", using: hasher) == nil)
    #expect(try access.streamedFile(below: root, path: "b/file", using: hasher) == nil)
  }

  @Test
  func `a symlink is never followed, on the way or at the end`() throws {
    try directory.write(".use-cases/outside/file.txt", "outside")
    try directory.makeDirectory(".use-cases/folder")
    try directory.symlink(".use-cases/folder/link", to: "../outside")
    try directory.symlink(".use-cases/folder/file-link", to: "../outside/file.txt")

    #expect(throws: StoreProblem.self) {
      try access.streamedFile(below: root, path: "link/file.txt", using: hasher)
    }
    #expect(throws: StoreProblem.self) {
      try access.streamedFile(below: root, path: "file-link", using: hasher)
    }
  }

  @Test
  func `a folder is not a file`() throws {
    try directory.makeDirectory(".use-cases/folder/a")

    #expect(throws: StoreProblem.self) {
      try access.streamedFile(below: root, path: "a", using: hasher)
    }
  }
}
