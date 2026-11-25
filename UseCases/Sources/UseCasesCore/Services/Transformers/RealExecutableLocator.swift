import Foundation

/// Where the running executable really is: the system's answer with every symlink resolved, so
/// that what sits beside it (the bundled transformers, chapter 10 §9) is found beside the file
/// itself and not beside a link to it.
public struct RealExecutableLocator: RunningExecutableLocating {
  private let executable: any RunningExecutableLocating
  private let fileSystem: any FileSystemReading

  /// Makes a locator that asks the system.
  public init() {
    self.init(
      executable: RunningExecutableLocator(),
      fileSystem: LocalFileSystem(),
    )
  }

  init(
    executable: any RunningExecutableLocating,
    fileSystem: any FileSystemReading,
  ) {
    self.executable = executable
    self.fileSystem = fileSystem
  }

  public func executableLocation() -> URL? {
    executable.executableLocation().map { location in
      fileSystem.canonicalLocation(of: location)
    }
  }
}
