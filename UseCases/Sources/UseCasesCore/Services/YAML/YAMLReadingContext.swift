/// What one read knows about the file in front of it.
struct YAMLReadingContext: Sendable {
  let file: String
  let kind: AuthoredFileKind
  let source: YAMLSourceText

  func location(line: Int) -> YAMLLocation {
    YAMLLocation(
      file: file,
      line: line,
    )
  }
}
