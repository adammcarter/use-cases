import Foundation

/// A program the tests run to ask other YAML readers, found where a package manager puts it.
enum InstalledTool {
  /// Where `name` is, looked for on the PATH and in the usual places; `nil` when it is not
  /// installed.
  static func location(of name: String) -> String? {
    let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
      + [
        "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin",
      ]

    return folders
      .map { folder in
        folder + "/" + name
      }
      .first { path in
        FileManager.default.isExecutableFile(atPath: path)
      }
  }

  static let uvProgram = location(of: "uv")

  static let rubyProgram = location(of: "ruby")

  static let goProgram = location(of: "go")
}
