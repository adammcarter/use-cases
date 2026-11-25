import Foundation

/// The standard input of this process.
struct StandardInputReader: StandardInputReading {
  func readText() throws(AuthoredInputError) -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()

    guard let text = String(
      data: data,
      encoding: .utf8,
    ) else {
      throw .notUTF8(name: AuthoredInputSource.standardInput.name)
    }

    return text
  }
}
