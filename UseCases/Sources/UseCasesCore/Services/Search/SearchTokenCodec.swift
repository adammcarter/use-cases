import Foundation

/// Tokens as base64url of compact JSON.
struct SearchTokenCodec: SearchTokenCoding {
  private let writer: any StoreJSONWriting
  private let json: any JSONReading

  init(
    writer: any StoreJSONWriting = StoreJSONWriter(),
    json: any JSONReading = JSONReader(),
  ) {
    self.writer = writer
    self.json = json
  }

  func token(for parameters: StoreJSONValue) -> String {
    Data(writer.compact(parameters))
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  func parameters(in token: String) throws(SearchTokenError) -> AuthoredValue {
    guard !token.isEmpty, token.utf8.allSatisfy(Self.isTokenCharacter) else {
      throw .malformed
    }

    let standard = token
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)

    guard
      let data = Data(base64Encoded: padded),
      let text = String(
        bytes: data,
        encoding: .utf8,
      )
    else {
      throw .malformed
    }

    do {
      return try json.read(text)
    } catch {
      throw .malformed
    }
  }

  private static func isTokenCharacter(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "a") ... UInt8(ascii: "z"),
         UInt8(ascii: "A") ... UInt8(ascii: "Z"),
         UInt8(ascii: "0") ... UInt8(ascii: "9"),
         UInt8(ascii: "-"),
         UInt8(ascii: "_"):
      true
    default:
      false
    }
  }
}
