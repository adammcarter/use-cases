import Testing
@testable import UseCasesCore

/// Text with one sentinel in it, and what the grammar reads there.
struct SentinelSample: Sendable, CustomTestStringConvertible {
  let text: String
  let kind: MarkerSentinelKind
  let identifier: String

  var testDescription: String {
    text.debugDescription
  }

  init(
    _ text: String,
    _ kind: MarkerSentinelKind,
    _ identifier: String,
  ) {
    self.text = text
    self.kind = kind
    self.identifier = identifier
  }
}
