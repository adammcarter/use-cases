import Foundation
@testable import UseCasesCore

/// A runner whose answer is whatever the test's closure makes of the request, so a test can do
/// something while the transformer "runs": change the report it is reading, or fail.
struct ClosureTransformerRunner: TransformerRunning {
  private let answer: @Sendable (StoreJSONValue) throws(TransformerError) -> AuthoredValue

  init(answer: @escaping @Sendable (StoreJSONValue) throws(TransformerError) -> AuthoredValue) {
    self.answer = answer
  }

  func run(
    _ reference: TransformerReference,
    job: TransformerJob,
    request: StoreJSONValue,
    in root: URL,
  ) async throws(TransformerError) -> AuthoredObject {
    let value = try answer(request)

    do {
      return try AuthoredObject(
        value,
        at: "",
      )
    } catch {
      throw .malformedResponse(name: reference.name, reason: "the test's answer is no object")
    }
  }
}
