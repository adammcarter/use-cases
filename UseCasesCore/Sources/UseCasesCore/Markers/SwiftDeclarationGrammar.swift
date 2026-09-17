/// The keyword sets and line tests the recognizer classifies declarations by.
enum SwiftDeclarationGrammar {
  /// Access and behaviour modifiers that may precede a declaration keyword.
  static let modifiers: Set<String> = [
    "public", "private", "internal", "fileprivate", "open", "static", "final", "override",
    "required", "convenience", "lazy", "weak", "unowned", "mutating", "nonmutating", "dynamic",
    "optional", "indirect", "prefix", "postfix", "infix", "nonisolated", "distributed", "unsafe",
    "borrowing", "consuming", "package",
  ]

  /// Declaration keywords that open a type body — an allowed enclosing scope.
  static let typeDeclarations: Set<String> = [
    "extension", "struct", "class", "enum", "protocol", "actor",
  ]

  /// Words that, met before a body brace, mean the func has no body.
  static let bodylessTerminators: Set<String> = [
    "func", "var", "let", "struct", "class", "enum", "protocol", "extension", "init", "deinit",
    "subscript", "typealias",
  ]

  /// The words after which a leading `class` is a type-member modifier.
  static let classMemberKeywords: Set<String> = ["func", "var", "subscript", "init"]

  /// The keywords that make a modifier line a complete declaration of its own.
  private static let declarationKeywords: [[UInt16]] = [
    "func", "var", "let", "init", "deinit", "subscript", "class", "struct", "enum", "protocol",
    "actor", "extension", "typealias", "case",
  ].map { keyword in
    Array(keyword.utf16)
  }

  private static let conditionalDirectives: [[UInt16]] = ["if", "elseif", "else", "endif"]
    .map { keyword in
      Array(keyword.utf16)
    }

  private static let ifDirective = [Array("if".utf16)]
  private static let endifDirective = [Array("endif".utf16)]

  /// `^[ \t]*$`.
  static func isBlank(_ text: [UInt16]) -> Bool {
    text.allSatisfy(CodeUnits.isSpaceOrTab)
  }

  /// The line with leading `[ \t]` removed.
  static func trimmed(_ text: [UInt16]) -> [UInt16] {
    Array(text.dropFirst(CodeUnits.spaceOrTabRun(text, from: 0)))
  }

  /// A line that begins an attached attribute or a bare modifier — part of a
  /// declaration group, so a marker below it sits inside the group (spec 9.2).
  static func startsAttachedDeclaration(_ text: [UInt16]) -> Bool {
    let line = trimmed(text)
    if line.first == CodeUnits.commercialAt {
      return true
    }
    guard let first = line.first, CodeUnits.isWordStart(first) else {
      return false
    }
    let wordLength = line.prefix { unit in
      CodeUnits.isWordCharacter(unit)
    }.count
    guard modifiers.contains(CodeUnits.string(line.prefix(wordLength))) else {
      return false
    }
    // A modifier line that also carries a declaration keyword is a separate,
    // complete declaration above the marker.
    return !containsDeclarationKeyword(line)
  }

  /// `/\b(func|var|…|case)\b/` anywhere in the line, with ASCII word boundaries.
  private static func containsDeclarationKeyword(_ line: [UInt16]) -> Bool {
    line.indices.contains { position in
      let boundaryBefore = position == 0 || !CodeUnits.isWordCharacter(line[position - 1])
      return boundaryBefore && CodeUnits.hasWord(line, at: position, among: declarationKeywords)
    }
  }

  /// `^#(if|elseif|else|endif)\b` on the trimmed line.
  static func isConditionalDirective(_ trimmedLine: [UInt16]) -> Bool {
    directive(trimmedLine, among: conditionalDirectives)
  }

  /// `^#if\b` on the trimmed line.
  static func opensConditional(_ trimmedLine: [UInt16]) -> Bool {
    directive(trimmedLine, among: ifDirective)
  }

  /// `^#endif\b` on the trimmed line.
  static func closesConditional(_ trimmedLine: [UInt16]) -> Bool {
    directive(trimmedLine, among: endifDirective)
  }

  private static func directive(
    _ trimmedLine: [UInt16],
    among names: [[UInt16]],
  ) -> Bool {
    trimmedLine.first == CodeUnits.numberSign && CodeUnits.hasWord(trimmedLine, at: 1, among: names)
  }
}
