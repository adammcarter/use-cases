import Testing
@testable import UseCasesCore

struct ScenarioLineTests {
  private func line(
    given: [String] = [],
    when: [String] = [],
    then: [String] = [],
  ) throws -> String {
    try Scenario(
      identifier: ScenarioIdentifier(validating: "on-state"),
      given: given,
      when: when,
      then: then,
    ).line
  }

  @Test
  func `a scenario is given G: W → T, each part's sentences without their full stops`() throws {
    #expect(
      try line(
        given: ["A 3.00 invoice.", "A coupon."],
        when: ["A 5.00 discount is applied."],
        then: ["The total is 0.00."],
      ) == "given A 3.00 invoice; A coupon: A 5.00 discount is applied → The total is 0.00",
    )
  }

  @Test
  func `a scenario with no given has none in the line`() throws {
    #expect(try line(when: ["It opens."], then: ["It shows."]) == "It opens → It shows")
  }

  @Test(arguments: [
    (["It opens."], [String](), "It opens"),
    ([String](), ["It shows."], "It shows"),
    ([String](), [String](), "on-state"),
  ])
  func `a scenario with only one of when and then shows that, and with neither its id`(
    when: [String],
    then: [String],
    expected: String,
  ) throws {
    #expect(try line(when: when, then: then) == expected)
  }

  @Test(arguments: [
    ("Done.", "Done"),
    ("Done", "Done"),
    ("Wait...", "Wait..."),
    (" Done. ", "Done"),
    ("Done.\n", "Done"),
  ])
  func `only one full stop at the end of a sentence is dropped`(
    sentence: String,
    expected: String,
  ) throws {
    #expect(try line(when: [sentence], then: ["x"]) == "\(expected) → x")
  }
}
