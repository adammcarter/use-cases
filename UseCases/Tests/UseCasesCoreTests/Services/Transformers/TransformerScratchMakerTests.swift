import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct TransformerScratchMakerTests {
  private let parent: TemporaryDirectory

  init() throws {
    parent = try TemporaryDirectory()
  }

  private func mode(of url: URL) throws -> mode_t {
    var information = stat()

    guard stat(url.path, &information) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return information.st_mode & 0o7777
  }

  @Test
  func `the folder is made in the parent, for this user alone`() throws {
    let scratch = try TransformerScratchMaker(parent: parent.url).makeScratch()

    #expect(scratch.folder.deletingLastPathComponent().path == parent.url.path)
    #expect(try mode(of: scratch.folder) == 0o700)
  }

  @Test
  func `every folder is a new one`() throws {
    let maker = TransformerScratchMaker(parent: parent.url)

    let first = try maker.makeScratch()
    let second = try maker.makeScratch()

    #expect(first.folder != second.folder)
  }

  @Test
  func `the request is written for this user alone, and is there to read`() throws {
    let scratch = try TransformerScratchMaker(parent: parent.url).makeScratch()

    try scratch.writeRequest(Array("{}".utf8))

    #expect(try mode(of: scratch.request) == 0o600)
    #expect(try String(contentsOf: scratch.request, encoding: .utf8) == "{}")
    #expect(scratch.request.lastPathComponent == "request.json")
    #expect(scratch.response.lastPathComponent == "response.json")
  }

  @Test
  func `a response nobody wrote is nil, and one that was written is its bytes`() throws {
    let scratch = try TransformerScratchMaker(parent: parent.url).makeScratch()

    #expect(try scratch.readResponse() == nil)

    try Data("[1]".utf8).write(to: scratch.response)

    #expect(try scratch.readResponse() == Array("[1]".utf8))
  }

  @Test
  func `removing the folder removes what is in it`() throws {
    let scratch = try TransformerScratchMaker(parent: parent.url).makeScratch()
    try scratch.writeRequest(Array("{}".utf8))

    scratch.remove()

    #expect(!FileManager.default.fileExists(atPath: scratch.folder.path))
  }

  @Test
  func `a parent that is not there is a failure to make the folder`() {
    let maker = TransformerScratchMaker(parent: parent.location(of: "missing"))

    #expect(throws: TransformerScratchError.self) {
      try maker.makeScratch()
    }
  }

  @Test
  func `a request that cannot be written is a failure`() throws {
    let scratch = try TransformerScratchMaker(parent: parent.url).makeScratch()
    scratch.remove()

    #expect(throws: TransformerScratchError
      .unavailable(reason: "request.json could not be written"))
    {
      try scratch.writeRequest([])
    }
  }
}
