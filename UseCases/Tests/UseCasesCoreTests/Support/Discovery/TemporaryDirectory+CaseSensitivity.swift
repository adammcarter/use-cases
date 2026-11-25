import Foundation

extension TemporaryDirectory {
  /// Whether this file system keeps two names that differ only in case, as Linux does and a
  /// default Mac volume does not.
  static var allowsNamesDifferingInCase: Bool {
    guard let directory = try? TemporaryDirectory() else {
      return false
    }

    try? directory.write("a", "")
    try? directory.write("A", "")

    return ((try? FileManager.default.contentsOfDirectory(atPath: directory.url.path)) ?? [])
      .count == 2
  }
}
