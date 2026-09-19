/// Section 9.4 ambiguity and unsupported-form codes. Every one is INVALID for
/// inferred mode: the author must write an explicit end instead. The raw values
/// are frozen wire contract (ADR 0007 decision 8).
public enum SwiftFunctionErrorCode: String, CaseIterable, Sendable {
  case noSwiftParser = "NO_SWIFT_PARSER"
  case swiftParseErrorInRegion = "SWIFT_PARSE_ERROR_IN_REGION"
  case markerNotAdjacentToDeclaration = "MARKER_NOT_ADJACENT_TO_DECLARATION"
  case markerInsideAttachedDeclaration = "MARKER_INSIDE_ATTACHED_DECLARATION"
  case nextNodeNotFunction = "NEXT_NODE_NOT_FUNC"
  case functionHasNoBody = "FUNC_HAS_NO_BODY"
  case functionBodyHasNoClosingBrace = "FUNC_BODY_HAS_NO_CLOSING_BRACE"
  case nestedFunctionUnsupported = "NESTED_FUNC_UNSUPPORTED"
  case conditionalCompilationInSpan = "CONDITIONAL_COMPILATION_IN_SPAN"
  case anotherMarkerInsideSpan = "ANOTHER_MARKER_INSIDE_SPAN"
  case multipleCandidateDeclarations = "MULTIPLE_CANDIDATE_DECLARATIONS"
}
