import Foundation

/// Finds the `use-cases` the build made, which sits beside the test bundle.
enum BuiltProgram {
  private final class BundleToken {}

  struct NotFound: Error {
    let searchedIn: String
  }

  static func url() throws -> URL {
    #if os(Linux)
      let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    #else
      let folder = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
    #endif
    let program = folder.appending(path: "use-cases")

    guard FileManager.default.isExecutableFile(atPath: program.path) else {
      throw NotFound(searchedIn: folder.path)
    }

    return program
  }
}
