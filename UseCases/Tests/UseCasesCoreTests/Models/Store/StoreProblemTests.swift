import Testing
@testable import UseCasesCore

struct StoreProblemTests {
  @Test
  func `each kind of problem reads as a sentence naming the place`() {
    #expect(StoreProblem.corrupt(".use-cases/runs/x/run.json", "bad").description
      == ".use-cases/runs/x/run.json is corrupt: bad")
    #expect(StoreProblem(location: ".use-cases/runs/latest", reason: .notARunFolder).description
      == ".use-cases/runs/latest is not a run folder")
    #expect(StoreProblem(location: ".use-cases", reason: .notAFolder).description
      == ".use-cases is not a folder")
    #expect(StoreProblem(location: "a", reason: .unreadable("denied")).description
      == "a cannot be read: denied")
    #expect(StoreProblem.unsupported("a", "too new").description == "a is unsupported: too new")
  }

  @Test
  func `problems sort by place then by wording`() {
    let problems = [
      StoreProblem.corrupt("b", "x"),
      StoreProblem.corrupt("a", "y"),
      StoreProblem.corrupt("a", "x"),
    ]

    #expect(problems.sorted().map(\.description) == [
      "a is corrupt: x",
      "a is corrupt: y",
      "b is corrupt: x",
    ])
  }

  @Test
  func `an unfinished run says it never finished`() {
    let run = UnfinishedRun(identifier: RunIdentifier.sample(42))

    #expect(run.description == "run 0000000000000000000000000000002a never finished")
  }
}
