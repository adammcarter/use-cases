/// Classifies every brace enclosing a position as a type body or anything else
/// (func body, closure, control flow, accessor). An inferred func is supported
/// only when every enclosing scope is a type body.
enum SwiftScopeAnalysis {
  static func enclosingScopesAreAllTypes(
    _ source: [UInt16],
    mask: SwiftCodeMask,
    until position: Int,
  ) -> Bool {
    var walker = ScopeWalker()
    for token in SwiftCodeTokenizer.tokenize(source, mask: mask, from: 0, to: position) {
      walker.consume(token)
    }
    return walker.scopesAreTypes.allSatisfy(\.self)
  }
}

private struct ScopeWalker {
  var scopesAreTypes: [Bool] = []
  var parenthesisDepth = 0
  var statementLead: String?

  private var leadIsType: Bool {
    statementLead.map(SwiftDeclarationGrammar.typeDeclarations.contains) ?? false
  }

  mutating func consume(_ token: SwiftCodeToken) {
    switch token.kind {
    case .leftParenthesis, .leftBracket:
      parenthesisDepth += 1
    case .rightParenthesis, .rightBracket:
      if parenthesisDepth > 0 {
        parenthesisDepth -= 1
      }
    case .newline:
      // A statement boundary at depth 0 — except that an in-flight TYPE lead
      // survives, so a multiline header (a where-clause) still opens a type.
      if parenthesisDepth == 0, !leadIsType {
        statementLead = nil
      }
    case .leftBrace:
      scopesAreTypes.append(leadIsType)
      statementLead = nil
    case .rightBrace:
      if !scopesAreTypes.isEmpty {
        scopesAreTypes.removeLast()
      }
      statementLead = nil
    case .word:
      consumeWord(token.text)
    case .attributeSign:
      break
    }
  }

  private mutating func consumeWord(_ word: String) {
    if SwiftDeclarationGrammar.modifiers.contains(word) {
      return
    }
    if statementLead == nil {
      statementLead = word
    } else if statementLead == "class", SwiftDeclarationGrammar.classMemberKeywords.contains(word) {
      // `class func` / `class var`: the leading `class` was a modifier.
      statementLead = word
    }
  }
}
