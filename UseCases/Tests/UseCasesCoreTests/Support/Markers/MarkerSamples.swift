import Foundation
@testable import UseCasesCore

/// Marker text and a way to scan it, for the tests of the marker scan.
enum MarkerSamples {
  /// A validation marker's id, and the start and end sentinels written around it.
  static let identifier = "example.success#unit-tests.success"
  static let open = MarkerText.sentinel + identifier
  static let close = "\(MarkerText.sentinel)end " + identifier

  /// The file every scan in these tests names.
  static let file = "tests/app_tests.swift"

  /// Scans text, as its UTF-8 bytes.
  static func scan(_ text: String) throws -> MarkerScan {
    try scan(bytes: Array(text.utf8))
  }

  /// Scans bytes.
  static func scan(bytes: [UInt8]) throws -> MarkerScan {
    try MarkerScanner().scan(
      bytes,
      in: workspacePath(file),
    )
  }

  /// The text a region holds: its content ranges joined.
  static func content(
    of region: MarkerRegion,
    in text: String,
  ) -> String {
    content(
      of: region,
      in: Array(text.utf8),
    )
  }

  /// The text a region holds in these bytes: its content ranges joined.
  static func content(
    of region: MarkerRegion,
    in bytes: [UInt8],
  ) -> String {
    let joined = region.contentRanges.flatMap { range in
      bytes[range]
    }

    return String(bytes: joined, encoding: .utf8) ?? ""
  }

  /// The diagnostics as a report prints them.
  static func rendered(_ scan: MarkerScan) -> [String] {
    scan.diagnostics.map(\.description)
  }
}
