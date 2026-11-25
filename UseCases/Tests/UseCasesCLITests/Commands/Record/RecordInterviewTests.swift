import Testing
import UseCasesCore
@testable import UseCasesCLI

struct RecordInterviewTests {
  private static let offers = [
    RecordOffer(
      useCase: "shop.pay",
      routes: [
        RecordRouteOffer(route: "unit-tests", steps: []),
        RecordRouteOffer(route: "by-hand", steps: ["Open it.", "Look."]),
      ],
    ),
    RecordOffer(
      useCase: "shop.cart",
      routes: [RecordRouteOffer(route: "unit-tests", steps: [])],
    ),
  ]

  private func interview(
    _ prompter: MockPrompter,
    offers: [RecordOffer] = Self.offers,
  ) async -> Result<RecordAnswers, RecordInterviewError> {
    do {
      return try await .success(RecordInterview(prompter: prompter).conduct(offers: offers))
    } catch {
      return .failure(error)
    }
  }

  private func conduct(_ answers: [String]) async -> (
    outcome: Result<RecordAnswers, RecordInterviewError>,
    transcript: [String],
  ) {
    let prompter = MockPrompter(answers: answers)
    let outcome = await interview(prompter)

    return await (outcome, prompter.transcript)
  }

  @Test
  func `the answers are the ids as the store spells them, whatever was typed`() async throws {
    let (outcome, _) = await conduct(["2", "unit", "fail", " it broke "])

    #expect(
      try outcome.get() == RecordAnswers(
        useCase: "shop.cart",
        route: "unit-tests",
        status: "fail",
        message: "it broke",
      ),
    )
  }

  @Test
  func `the steps of a route are shown after it is chosen, and before the result is asked`(
  ) async {
    let (_, transcript) = await conduct(["shop.pay", "by-hand", "pass", ""])

    #expect(
      transcript == [
        "Use case?  1 shop.pay   2 shop.cart",
        "           > ",
        "Route?     1 unit-tests   2 by-hand",
        "           > ",
        "           Steps: 1. Open it.  2. Look.",
        "Result?    pass / fail / incomplete / error",
        "           > ",
        "Note?      (optional) > ",
      ],
    )
  }

  @Test(arguments: ["verified", "PASS", "p", "", "1"])
  func `a result the store does not keep is refused at once, before the note is asked`(
    status: String,
  ) async {
    let (outcome, transcript) = await conduct(["1", "1", status, "never asked"])

    #expect(throws: RecordInterviewError.recording(.unknownStatus(status))) {
      try outcome.get()
    }
    #expect(transcript.last == "           > ")
  }

  @Test
  func `nothing to offer is a refusal that asks nothing`() async {
    let prompter = MockPrompter(answers: ["x"])

    let outcome = await interview(
      prompter,
      offers: [],
    )

    #expect(throws: RecordInterviewError.recording(.noReadyUseCase)) {
      try outcome.get()
    }
    #expect(await prompter.transcript.isEmpty)
  }

  @Test(arguments: 0 ..< 4)
  func `input that ends is told, wherever it ends`(answered: Int) async {
    let (outcome, _) = await conduct(Array(["1", "1", "pass", ""].prefix(answered)))

    #expect(throws: RecordInterviewError.inputEnded) {
      try outcome.get()
    }
  }

  @Test
  func `an answer that is refused stops the questions`() async {
    let (outcome, transcript) = await conduct(["shop", "1"])

    #expect(
      throws: RecordInterviewError.recording(
        .ambiguousUseCase(
          "shop",
          matching: ["shop.cart", "shop.pay"],
        ),
      ),
    ) {
      try outcome.get()
    }
    #expect(transcript.count == 2)
  }
}
