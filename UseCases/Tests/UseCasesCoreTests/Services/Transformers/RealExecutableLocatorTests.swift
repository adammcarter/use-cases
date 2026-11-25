import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct RealExecutableLocatorTests {
  @Test
  func `a link to the executable is answered with the file it leads to`() throws {
    let folder = try TemporaryDirectory()
    try folder.write("real/use-cases", "#!/bin/sh\n")
    try FileManager.default.createDirectory(
      at: folder.location(of: "bin"),
      withIntermediateDirectories: true,
    )
    try FileManager.default.createSymbolicLink(
      at: folder.location(of: "bin/use-cases"),
      withDestinationURL: folder.location(of: "real/use-cases"),
    )
    let locator = RealExecutableLocator(
      executable: MockRunningExecutableLocating(at: folder.location(of: "bin/use-cases")),
      fileSystem: LocalFileSystem(),
    )

    #expect(locator.executableLocation() == folder.location(of: "real/use-cases"))
  }

  @Test
  func `an executable the system cannot place is not found`() {
    let locator = RealExecutableLocator(
      executable: MockRunningExecutableLocating(at: nil),
      fileSystem: LocalFileSystem(),
    )

    #expect(locator.executableLocation() == nil)
  }

  @Test
  func `the running test program is found, by a path that exists`() throws {
    let location = try #require(RealExecutableLocator().executableLocation())

    #expect(FileManager.default.fileExists(atPath: location.path))
  }
}
