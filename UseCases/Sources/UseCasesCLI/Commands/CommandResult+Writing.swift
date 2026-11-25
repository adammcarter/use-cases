import Foundation

extension CommandResult {
  /// Writes both streams.
  func write() {
    FileHandle.standardOutput.write(Data(standardOutput.utf8))
    FileHandle.standardError.write(Data(standardError.utf8))
  }
}
