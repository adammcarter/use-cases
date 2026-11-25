import Foundation
@testable import UseCasesCore

/// A runner that answers each call with the next canned answer, and keeps what it was asked.
actor MockTransformerRunner: TransformerRunning {
  struct Call: Equatable {
    let reference: TransformerReference
    let job: TransformerJob
    let request: StoreJSONValue
  }

  private var answers: [Result<AuthoredValue, TransformerError>]
  private(set) var calls: [Call] = []

  /// Each call takes the next answer; a call with none left is a failure of the test.
  init(answers: [Result<AuthoredValue, TransformerError>]) {
    self.answers = answers
  }

  func run(
    _ reference: TransformerReference,
    job: TransformerJob,
    request: StoreJSONValue,
    in root: URL,
  ) async throws(TransformerError) -> AuthoredObject {
    calls.append(
      Call(
        reference: reference,
        job: job,
        request: request,
      ),
    )

    guard !answers.isEmpty else {
      throw .couldNotLaunch(name: reference.name, reason: "the test gave no answer")
    }

    do {
      return try AuthoredObject(
        answers.removeFirst().get(),
        at: "",
      )
    } catch let error as TransformerError {
      throw error
    } catch {
      throw .malformedResponse(name: reference.name, reason: "the test's answer is no object")
    }
  }
}
