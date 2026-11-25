import Foundation

/// Says how much space a folder of the store takes.
protocol StoreMeasuring: Sendable {
  /// The total size, in bytes, of the regular files below a folder; a symlink is never followed
  /// and counts nothing. A folder that is not there takes none.
  func bytes(below folder: URL) -> Int64
}
