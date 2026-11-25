/// The problems the marker scan reports, with their wording in one place (chapter 08).
extension Diagnostic {
  /// A file that holds `@use-case:` but is not strict UTF-8.
  static func notStrictUTF8(_ file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      file: file,
      position: nil,
      code: .unsupportedText,
      severity: .warning,
      message: "unsupported-text: the file holds '@use-case:' but is not strict UTF-8, "
        + "so its markers cannot be read",
    )
  }

  /// A file that starts with a UTF-16 or UTF-32 byte-order mark.
  static func wideByteOrderMark(_ file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      file: file,
      position: nil,
      code: .unsupportedText,
      severity: .warning,
      message: "unsupported-text: the file starts with a UTF-16 or UTF-32 byte-order mark, "
        + "so its markers cannot be read",
    )
  }

  /// A sentinel whose id is not a marker id: ignored, and not part of pairing.
  static func malformedMarkerIdentifier(
    _ sentinel: MarkerSentinel,
    in file: WorkspacePath,
    because error: MarkerTargetError,
  ) -> Diagnostic {
    markerDiagnostic(
      file: file,
      line: sentinel.line,
      code: .malformedMarkerIdentifier,
      severity: .warning,
      message: "malformed marker id '\(sentinel.identifier)': \(error)",
    )
  }

  /// A region with no content.
  static func emptyMarkerRegion(
    _ region: MarkerRegion,
    in file: WorkspacePath,
  ) -> Diagnostic {
    markerDiagnostic(
      file: file,
      line: region.startLine,
      code: .emptyMarkerRegion,
      severity: .warning,
      message: emptyMarkerRegionMessage("\(region.target)"),
    )
  }

  /// What the warning for a region says; `target` is `<use case>#[<route>.]<binding>`.
  static func emptyMarkerRegionMessage(_ target: String) -> String {
    "empty marker region: \(target)"
  }

  /// The way out of a pairing problem for a file that is not code: test data, a fixture or build
  /// output that holds marker text as data (chapter 08).
  static let markerTextAsData = "if this file holds marker text as data, exclude it with "
    + "discovery.exclude in use-cases.yml"

  /// A pairing problem, which makes the workspace INVALID.
  static func markerPairing(
    _ problem: MarkerPairingProblem,
    in file: WorkspacePath,
  ) -> Diagnostic {
    switch problem {
    case let .neverClosed(start):
      markerDiagnostic(
        file: file,
        line: start.line,
        code: .markerNeverClosed,
        severity: .error,
        message: "marker '\(start.identifier)' is never closed: "
          + "no '@use-case:end \(start.identifier)' follows it; \(Self.markerTextAsData)",
      )
    case let .withoutStart(end):
      markerDiagnostic(
        file: file,
        line: end.line,
        code: .markerWithoutStart,
        severity: .error,
        message: "the end of marker '\(end.identifier)' has no start before it; "
          + Self.markerTextAsData,
      )
    case let .crossing(end, start, stillOpen):
      markerDiagnostic(
        file: file,
        line: end.line,
        code: .markersCross,
        severity: .error,
        message: "markers '\(start.identifier)' (from line \(start.line)) and "
          + "'\(stillOpen.identifier)' (from line \(stillOpen.line)) cross: "
          + "'\(start.identifier)' ends before '\(stillOpen.identifier)' does",
      )
    case let .nestedInItself(start, outer):
      markerDiagnostic(
        file: file,
        line: start.line,
        code: .markerNestedInItself,
        severity: .error,
        message: "marker '\(start.identifier)' is nested inside itself: "
          + "it is already open from line \(outer.line)",
      )
    }
  }

  private static func markerDiagnostic(
    file: WorkspacePath,
    line: Int,
    code: DiagnosticCode,
    severity: DiagnosticSeverity,
    message: String,
  ) -> Diagnostic {
    Diagnostic(
      file: file,
      position: try? SourcePosition(line: line),
      code: code,
      severity: severity,
      message: message,
    )
  }
}
