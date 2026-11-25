/// A folder inside the workspace, spelled the way the contract spells paths: `/` separators, no
/// leading, trailing or doubled `/`, no `.` or `..` parts.
enum FolderPath {
  /// `text` in that spelling ("" for the code root itself), or nil when it cannot name a folder
  /// inside the workspace: an absolute path, a drive letter, a backslash, a control character or
  /// a `..` part.
  static func normalised(_ text: String) -> String? {
    guard
      !text.hasPrefix("/"),
      !text.contains("\\"),
      !text.unicodeScalars
      .contains(where: { scalar in scalar.value < 0x20 || scalar.value == 0x7F }),
      !FolderPath.hasDriveLetter(text)
    else {
      return nil
    }

    let parts = text.split(
      separator: "/",
      omittingEmptySubsequences: true,
    ).filter { part in
      part != "."
    }

    guard !parts.contains("..") else {
      return nil
    }

    return parts.joined(separator: "/")
  }

  private static func hasDriveLetter(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars.prefix(2))

    return scalars.count == 2 && scalars[1] == ":" && scalars[0].properties.isAlphabetic
  }
}
