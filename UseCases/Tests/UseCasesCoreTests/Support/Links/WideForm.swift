@testable import UseCasesCore

/// The four ways a wide text file starts.
enum WideForm: CaseIterable {
  case utf16Little
  case utf16Big
  case utf32Little
  case utf32Big

  func bytes(of text: String) -> [UInt8] {
    switch self {
    case .utf16Little:
      WideEncoding.utf16(text, bigEndian: false)
    case .utf16Big:
      WideEncoding.utf16(text, bigEndian: true)
    case .utf32Little:
      WideEncoding.utf32(text, bigEndian: false)
    case .utf32Big:
      WideEncoding.utf32(text, bigEndian: true)
    }
  }
}
