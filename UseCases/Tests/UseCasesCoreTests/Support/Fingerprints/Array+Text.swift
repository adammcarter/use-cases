import Foundation

extension [UInt8] {
  /// The bytes read as UTF-8 text; empty when they are not.
  var utf8Text: String {
    String(bytes: self, encoding: .utf8) ?? ""
  }
}
