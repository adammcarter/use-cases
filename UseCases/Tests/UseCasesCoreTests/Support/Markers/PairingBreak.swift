import Testing
@testable import UseCasesCore

/// A file whose markers do not pair: what it holds, and the one error it is told with.
struct PairingBreak: Sendable, CustomTestStringConvertible {
  let text: String
  let code: DiagnosticCode
  let line: Int
  let wording: String

  var testDescription: String {
    wording
  }
}
