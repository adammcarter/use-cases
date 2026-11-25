/// The folders discovery never enters, whatever the workspace says: the tool's own store and
/// version-control history, at any depth (chapter 04, ADR 012).
enum DefaultDiscoveryExclusions {
  static let patternTexts = [
    "**/.use-cases/**",
    "**/.git/**",
    "**/.hg/**",
    "**/.svn/**",
    "**/.bzr/**",
    "**/.jj/**",
  ]

  static var patterns: [PathPattern] {
    patternTexts.compactMap { text in
      try? PathPattern(validating: text)
    }
  }
}
