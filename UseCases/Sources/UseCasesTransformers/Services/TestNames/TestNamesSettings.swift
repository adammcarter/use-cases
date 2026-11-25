/// The `settings` of the `test-names` transformer.
struct TestNamesSettings {
  /// The glob of files to search, from the workspace root.
  let files: String
  /// A regular expression with a named group `id` capturing a marker-style id.
  let pattern: Regex<AnyRegexOutput>
  let block: LinkBlock

  init(settings: TransformerSettings) throws(TransformerFailure) {
    files = try settings.requiredString("files")

    let patternText = try settings.requiredString("pattern")

    guard let pattern = try? Regex(patternText) else {
      throw .settingInvalid(
        name: "pattern",
        expected: "a valid regular expression",
      )
    }

    self.pattern = pattern

    let blockName = try settings.string("block") ?? LinkBlock.line.rawValue

    guard let block = LinkBlock(rawValue: blockName) else {
      throw .settingInvalid(
        name: "block",
        expected: "line or braces",
      )
    }

    self.block = block
  }
}
