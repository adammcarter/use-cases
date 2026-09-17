/// Schema and algorithm identifiers for the use-case marker system.
///
/// Each one is written into registry events, proof events or ledgers, so the
/// strings are frozen contract (ADR 0007 decision 8).
public enum MarkerConstants {
  public static let markerSchemaIdentifier = "ucase-marker-v1"
  public static let bindingRegistrySchemaIdentifier = "ucase-binding-registry-event-v1"
  public static let evidenceSchemaIdentifier = "ucase-proof-event-v1"
  public static let statusSchemaIdentifier = "ucase-freshness-status-v1"

  public static let spanCanonicalizerIdentifier = "ucase-span-lines-v2"
  public static let explicitRecognizerIdentifier = "explicit-span-v1"
  public static let swiftFunctionRecognizerIdentifier = "swift-func-inferred-v1"
  public static let bindingSetHashIdentifier = "ucase-binding-set-v1"

  /// Names the existing semantic row-hash algorithm the marker system reuses.
  public static let rowHashIdentifier = "existing-semantic-row-hash"
}
