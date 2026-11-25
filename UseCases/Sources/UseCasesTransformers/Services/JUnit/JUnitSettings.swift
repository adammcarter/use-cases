/// The `settings` of the `junit` transformer.
struct JUnitSettings: Equatable, Sendable {
  let find: JUnitFindMode
  /// 0 when the report counts lines from 0; 1 otherwise.
  let lineBase: Int
  /// The folder the report's relative paths start from; the working folder when nil.
  let base: String?
  /// The glob of source files a `pattern` search covers.
  let files: String?
  /// Declarations to look for; `{name}` is the test name and `{method}` the name before any `(`.
  let patterns: [String]
  /// Whether a `pattern` search covers only the file named after the test's outer class.
  let usesClassFile: Bool

  init(settings: TransformerSettings) throws(TransformerFailure) {
    let findName = try settings.string("find") ?? JUnitFindMode.fileLine.rawValue

    guard let find = JUnitFindMode(rawValue: findName) else {
      throw .settingInvalid(
        name: "find",
        expected: "file-line, file-name or pattern",
      )
    }

    self.find = find
    lineBase = try settings.integer("line_base") ?? 1

    guard (-LineRange.largest ... LineRange.largest).contains(lineBase) else {
      throw .settingInvalid(
        name: "line_base",
        expected: "a small whole number",
      )
    }

    base = try settings.string("base")
    files = try settings.string("files")
    patterns = try settings.strings("patterns") ?? []
    usesClassFile = try settings.boolean("class_file") ?? false

    if find == .pattern {
      guard files != nil else {
        throw .settingMissing("files")
      }

      guard !patterns.isEmpty else {
        throw .settingMissing("patterns")
      }
    }
  }
}
