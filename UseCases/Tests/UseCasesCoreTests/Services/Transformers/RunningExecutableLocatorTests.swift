import Foundation
import Testing
@testable import UseCasesCore

struct RunningExecutableLocatorTests {
  @Test
  func `the running executable is found, and it is a file that is there`() throws {
    let location = try #require(RunningExecutableLocator().executableLocation())
    var isDirectory: ObjCBool = true

    #expect(location.path.hasPrefix("/"))
    #expect(FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory))
    #expect(!isDirectory.boolValue)
  }

  @Test
  func `it is the executable the process was started from`() throws {
    let location = try #require(RunningExecutableLocator().executableLocation())
    let started = try #require(Bundle.main.executableURL)
    let fileSystem = LocalFileSystem()

    #expect(fileSystem.canonicalLocation(of: location) == fileSystem.canonicalLocation(of: started))
  }
}
