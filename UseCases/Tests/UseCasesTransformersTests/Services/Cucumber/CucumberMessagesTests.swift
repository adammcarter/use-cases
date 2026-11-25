import Testing
@testable import UseCasesTransformers

struct CucumberMessagesTests {
  private typealias Stream = CucumberStream

  @Test(arguments: [
    (["PASSED", "PASSED"], ResultStatus.pass),
    (["PASSED", "FAILED"], .fail),
    (["PASSED", "AMBIGUOUS"], .error),
    (["PASSED", "PENDING"], .incomplete),
    (["PASSED", "UNDEFINED"], .incomplete),
    (["PASSED", "SKIPPED"], .incomplete),
    (["PASSED", "UNKNOWN"], .incomplete),
    (["AMBIGUOUS", "FAILED"], .fail),
    (["PENDING", "AMBIGUOUS"], .error),
    (["PASSED", "SOMETHING_NEW"], .incomplete),
    ([], .incomplete),
  ])
  func `the steps of a scenario decide its result`(
    steps: [String],
    expected: ResultStatus,
  ) {
    let messages = CucumberMessages(text: Stream.stream(Stream.scenario(
      "s",
      line: 3,
      steps: steps,
    )))

    #expect(messages.scenarios.map(\.status) == [expected])
  }

  @Test
  func `a scenario is placed at its own line in its feature file`() {
    let messages = CucumberMessages(
      text: Stream.stream(Stream.scenario(
        "Late returns",
        uri: "features/returns.feature",
        line: 9,
        steps: ["PASSED"],
      )),
    )

    #expect(
      messages.scenarios.map(\.pickle) == [
        CucumberPickle(
          uri: "features/returns.feature",
          name: "Late returns",
          line: 9,
        ),
      ],
    )
  }

  @Test
  func `when a scenario is retried only its last attempt counts`() {
    let lines = [
      Stream.pickle(
        "p",
        uri: "f.feature",
        name: "n",
        line: 3,
      ),
      Stream.testCase(
        "c",
        pickle: "p",
      ),
      Stream.started(
        "s0",
        testCase: "c",
        attempt: 0,
      ),
      Stream.step(
        "FAILED",
        start: "s0",
      ),
      Stream.started(
        "s1",
        testCase: "c",
        attempt: 1,
      ),
      Stream.step(
        "PASSED",
        start: "s1",
      ),
    ]

    #expect(CucumberMessages(text: Stream.stream(lines)).scenarios.map(\.status) == [.pass])
  }

  @Test
  func `the last attempt counts even when its messages come first`() {
    let lines = [
      Stream.pickle(
        "p",
        uri: "f.feature",
        name: "n",
        line: 3,
      ),
      Stream.testCase(
        "c",
        pickle: "p",
      ),
      Stream.started(
        "s1",
        testCase: "c",
        attempt: 1,
      ),
      Stream.step(
        "FAILED",
        start: "s1",
      ),
      Stream.started(
        "s0",
        testCase: "c",
        attempt: 0,
      ),
      Stream.step(
        "PASSED",
        start: "s0",
      ),
    ]

    #expect(CucumberMessages(text: Stream.stream(lines)).scenarios.map(\.status) == [.fail])
  }

  @Test
  func `a scenario that never started is not a test`() {
    let lines = [
      Stream.pickle(
        "p",
        uri: "f.feature",
        name: "filtered out",
        line: 3,
      ),
      Stream.testCase(
        "c",
        pickle: "p",
      ),
    ]

    #expect(CucumberMessages(text: Stream.stream(lines)).scenarios.isEmpty)
  }

  @Test
  func `scenarios come in file and line order`() {
    let lines = Stream.scenario(
      "b",
      uri: "b.feature",
      line: 1,
      steps: ["PASSED"],
    )
      + Stream.scenario(
        "a2",
        uri: "a.feature",
        line: 9,
        steps: ["PASSED"],
      )
      + Stream.scenario(
        "a1",
        uri: "a.feature",
        line: 2,
        steps: ["PASSED"],
      )

    #expect(CucumberMessages(text: Stream.stream(lines)).scenarios.map(\.pickle.name) == [
      "a1",
      "a2",
      "b",
    ])
  }

  @Test
  func `lines that are not messages are noted and skipped`() {
    let text = "not json\n{\"pickle\": {\"id\": \"p\"}}\n{\"testStepFinished\": {}}\n"
      + Stream.stream(Stream.scenario(
        "ok",
        line: 3,
        steps: ["PASSED"],
      ))

    let messages = CucumberMessages(text: text)

    #expect(
      messages.diagnostics == [
        "line 1 is not a message; ignored",
        "line 2 is not a message; ignored",
        "line 3 is not a message; ignored",
      ],
    )
    #expect(messages.scenarios.map(\.status) == [.pass])
  }

  @Test
  func `a scenario the stream gives no location is noted, never guessed at`() {
    let lines = [
      jsonLine(["pickle": ["id": "p", "uri": "f.feature", "name": "no place"]]),
      Stream.testCase(
        "c",
        pickle: "p",
      ),
      Stream.started(
        "s",
        testCase: "c",
      ),
      Stream.step(
        "PASSED",
        start: "s",
      ),
    ]

    let messages = CucumberMessages(text: Stream.stream(lines))

    #expect(messages.scenarios.isEmpty)
    #expect(messages.diagnostics == ["line 1: the scenario 'no place' has no location; ignored"])
  }

  @Test
  func `messages of other kinds and blank lines are fine`() {
    let messages = CucumberMessages(
      text: """
      {"meta": {"protocolVersion": "1"}}

      {"gherkinDocument": {}}
      {"testRunFinished": {}}
      """,
    )

    #expect(messages.diagnostics.isEmpty)
    #expect(messages.scenarios.isEmpty)
  }
}
