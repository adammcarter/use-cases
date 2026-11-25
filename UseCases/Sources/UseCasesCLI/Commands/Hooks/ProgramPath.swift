import Foundation

/// The full path of the `use-cases` that is running, as it was run: made absolute, with every
/// link in it kept and none resolved, so that an upgrade that moves the real program does not
/// break a hook that remembers the path (chapter 18 §3).
struct ProgramPath: Equatable {
  /// The place a hook falls back on when no `use-cases` has been found to remember.
  static let installed = "/opt/use-cases/bin/use-cases"

  let text: String

  /// A program known by its full path.
  init(installedAt text: String) {
    self.text = text
  }

  /// - Parameters:
  ///   - command: How the program was started: the first word of the command line.
  ///   - workingDirectory: Where it was started, which a relative path is read from.
  ///   - searchPath: The PATH, which a bare name is looked for in.
  ///   - isExecutable: Whether a file at a path can be run.
  init(
    command: String,
    workingDirectory: URL,
    searchPath: String?,
    isExecutable: (String) -> Bool,
  ) {
    guard !command.contains("/") else {
      text = Self.absolute(
        command,
        in: workingDirectory.path,
      )

      return
    }

    let folders = (searchPath ?? "").split(
      separator: ":",
      omittingEmptySubsequences: true,
    )

    let found = folders.map { folder in
      Self.absolute(
        "\(folder)/\(command)",
        in: workingDirectory.path,
      )
    }.first(where: isExecutable)

    text = found ?? Self.absolute(
      command,
      in: workingDirectory.path,
    )
  }

  /// The path from the folder it is read from, without a `.` or an empty part. A `..` stays: it
  /// means the parent of the real folder before it, which only the file system knows.
  private static func absolute(
    _ path: String,
    in folder: String,
  ) -> String {
    let whole = path.hasPrefix("/") ? path : folder + "/" + path

    let parts = whole.split(
      separator: "/",
      omittingEmptySubsequences: true,
    ).filter { part in
      part != "."
    }

    return "/" + parts.joined(separator: "/")
  }
}
