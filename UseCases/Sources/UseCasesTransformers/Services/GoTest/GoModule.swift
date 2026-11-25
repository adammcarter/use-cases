/// The module a Go project declares in `go.mod`.
struct GoModule: Equatable, Sendable {
  let path: String

  /// Reads the `module` line of the `go.mod` at `file`.
  init(
    modFile file: String,
    reader: any ReportReading,
  ) throws(TransformerFailure) {
    guard reader.exists(at: file) else {
      throw .reportUnreadable(
        path: file,
        reason: "go.mod not found",
      )
    }

    let text = try reader.text(at: file)
    let declaration = text.reportLines.first { line in
      line.hasPrefix("module ")
    }
    let words = declaration?.split(whereSeparator: \.isWhitespace) ?? []

    guard words.count >= 2 else {
      throw .reportMalformed(
        path: file,
        reason: "go.mod has no module line",
      )
    }

    path = String(words[1])
  }

  /// The folder of `package` below the module root ("" for the root), or nil when the package is
  /// not part of this module.
  func folder(ofPackage package: String) -> String? {
    if package == path {
      return ""
    }

    guard package.hasPrefix(path + "/") else {
      return nil
    }

    return String(package.dropFirst(path.count + 1))
  }
}
