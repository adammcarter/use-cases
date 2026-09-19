/// Every way a marker or an explicit span can be invalid. The raw values are
/// frozen wire contract (ADR 0007 decision 8).
///
/// Marker-line codes come from ``MarkerLineParser``; span-pairing codes come from
/// ``MarkerScanner``.
public enum MarkerErrorCode: String, CaseIterable, Sendable {
  // Marker-line level.
  case forbiddenMarkerPayload = "FORBIDDEN_MARKER_PAYLOAD"
  case malformedMarker = "MALFORMED_MARKER"
  case malformedEndMarker = "MALFORMED_END_MARKER"
  // Span-pairing level.
  case mismatchedEndMarker = "MISMATCHED_END_MARKER"
  case endWithoutStart = "END_WITHOUT_START"
  case unsupportedInference = "UNSUPPORTED_INFERENCE"
  case nestedSpan = "NESTED_SPAN"
  case unbalancedIgnore = "UNBALANCED_IGNORE"
  case duplicateBindingSlug = "DUPLICATE_BINDING_SLUG"
}
