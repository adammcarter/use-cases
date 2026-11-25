import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Asks the system for the running executable: `_NSGetExecutablePath` on Darwin and
/// `/proc/self/exe` on Linux.
public struct RunningExecutableLocator: RunningExecutableLocating {
  /// Makes a locator.
  public init() {}

  public func executableLocation() -> URL? {
    guard let path = Self.systemPath() else {
      return nil
    }

    return URL(fileURLWithPath: path)
  }

  #if canImport(Darwin)
    private static func systemPath() -> String? {
      var size = UInt32(PATH_MAX)
      var buffer = [CChar](repeating: 0, count: Int(size))

      if _NSGetExecutablePath(&buffer, &size) != 0 {
        // The first buffer was too small; `size` now says how large one must be.
        buffer = [CChar](repeating: 0, count: Int(size))

        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
          return nil
        }
      }

      return text(of: buffer)
    }
  #else
    private static func systemPath() -> String? {
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
      let length = readlink("/proc/self/exe", &buffer, Int(PATH_MAX))

      guard length > 0 else {
        return nil
      }

      buffer[length] = 0

      return text(of: buffer)
    }
  #endif

  /// The text up to the first zero byte.
  private static func text(of buffer: [CChar]) -> String? {
    let bytes: [UInt8] = buffer.prefix { character in
      character != 0
    }.map { character in
      UInt8(bitPattern: character)
    }

    guard !bytes.isEmpty else {
      return nil
    }

    return bytes.lossyUTF8Text
  }
}
