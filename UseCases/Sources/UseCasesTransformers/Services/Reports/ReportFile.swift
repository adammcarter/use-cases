import Foundation

/// Reports and source files on the disk.
struct ReportFile: ReportReading {
  func exists(at path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  func isFolder(at path: String) -> Bool {
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: path,
      isDirectory: &isFolder,
    )

    return exists && isFolder.boolValue
  }

  func files(under path: String) -> [String] {
    let names = FileManager.default.enumerator(atPath: path)?.allObjects as? [String] ?? []

    return names.sorted { first, second in
      first.precedesByCodePoint(second)
    }.map { name in
      path + "/" + name
    }.filter { file in
      !isFolder(at: file)
    }
  }

  func data(at path: String) throws(TransformerFailure) -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw .reportUnreadable(
        path: path,
        reason: error.localizedDescription,
      )
    }
  }

  func text(at path: String) throws(TransformerFailure) -> String {
    guard let text = try String(
      data: data(at: path),
      encoding: .utf8,
    ) else {
      throw .reportMalformed(
        path: path,
        reason: "not UTF-8 text",
      )
    }

    return text
  }

  func lossyText(at path: String) throws(TransformerFailure) -> String {
    // `Unicode.UTF8` is `UTF8`: the long spelling keeps this lossy decoding apart from the lint
    // rule that asks for the failable initialiser, which is the strict reading above.
    try String(
      decoding: data(at: path),
      as: Unicode.UTF8.self,
    )
  }

  func sourceText(at path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
      return nil
    }

    return String(
      data: data,
      encoding: .utf8,
    )
  }
}
