import Testing
@testable import UseCasesCore

struct UseCaseBatchReaderTests {
  private func reader(sending json: String) throws -> UseCaseBatchReader {
    try UseCaseBatchReader(
      reader: MockAuthoredInput(AuthoredInput(name: "stdin", value: authored(json))),
      checker: UseCaseInputChecker(),
    )
  }

  private func read(_ json: String) throws -> UseCaseBatch {
    try reader(sending: json).read("-")
  }

  /// What reading the input refuses with; `nil` when it reads.
  private func refusal(of json: String) throws -> UseCaseBatchError? {
    let reader = try reader(sending: json)

    do {
      _ = try reader.read("-")

      return nil
    } catch {
      return error
    }
  }

  @Test
  func `removals and saves are read in the order the file lists them`() throws {
    let batch = try read(
      """
      {"save": [{"id": "app.dark.b", "title": "B"}, {"id": "app.dark.a", "title": "A"}],
       "remove": ["app.dark.y", "app.dark.x"]}
      """,
    )

    #expect(batch.removals == ["app.dark.y", "app.dark.x"])
    #expect(batch.saves.map(\.identifier.text) == ["app.dark.b", "app.dark.a"])
    #expect(batch.saves.map(\.definition.title) == ["B", "A"])
  }

  @Test
  func `input that is already read is the batch it holds, and the reader is not asked`() throws {
    let reader = UseCaseBatchReader(
      reader: MockAuthoredInput(failing: .notAFile(path: "never.yml")),
      checker: UseCaseInputChecker(),
    )

    let batch = try reader.batch(
      from: AuthoredInput(
        name: "p.yml",
        value: authored(#"{"remove": ["app.dark.x"]}"#),
      ),
    )

    #expect(batch.removals == ["app.dark.x"])
    #expect(throws: UseCaseBatchError.notABatch(
      name: "p.yml",
      problem: "this one changes nothing",
    )) {
      try reader.batch(from: AuthoredInput(name: "p.yml", value: authored("{}")))
    }
  }

  @Test
  func `either list alone is a batch`() throws {
    #expect(try read(#"{"remove": ["app.dark.x"]}"#).saves.isEmpty)
    #expect(try read(#"{"save": [{"id": "app.dark.x", "title": "X"}]}"#).removals.isEmpty)
  }

  @Test
  func `the six keys of a proposal file are accepted whatever they hold, and ignored`() throws {
    let batch = try read(
      """
      {"title": "Lock accounts", "untouched": ["app.dark.x"], "fits": {"app.dark.y": "extends"},
       "you_see": 3, "decisions": null, "golden": [[1, 2]],
       "remove": ["app.dark.z"]}
      """,
    )

    #expect(batch.removals == ["app.dark.z"])
    #expect(batch.saves.isEmpty)
  }

  @Test(arguments: [
    "{}",
    "[]",
    "\"remove\"",
    "7",
    #"{"remove": [], "save": []}"#,
    #"{"title": "only a proposal"}"#,
  ])
  func `an input that changes nothing is not a batch`(json: String) throws {
    let refused = try #require(try refusal(of: json))

    #expect(refused.message.contains("a batch is a mapping"))
    #expect(refused.kind == .usage)
  }

  @Test(arguments: ["rename", "Remove", "removes", "use_cases"])
  func `a key that is not a batch's is named`(key: String) throws {
    let json = "{\"remove\": [\"app.dark.x\"], \"" + key + "\": []}"
    let refused = try #require(try refusal(of: json))

    #expect(
      refused == .notABatch(
        name: "stdin",
        problem: "'\(key)' is not a key of a batch",
      ),
    )
    #expect(refused.message.contains("a batch is a mapping"))
  }

  @Test
  func `a blank remove or a blank save is an empty list`() throws {
    let removing = try read(#"{"remove": null, "save": [{"id": "app.dark.a", "title": "A"}]}"#)
    let saving = try read(#"{"remove": ["app.dark.x"], "save": null}"#)

    #expect(removing.removals.isEmpty)
    #expect(removing.saves.count == 1)
    #expect(saving.removals == ["app.dark.x"])
    #expect(saving.saves.isEmpty)
  }

  @Test(arguments: [#"{"remove": null}"#, #"{"save": null}"#, #"{"remove": null, "save": null}"#])
  func `a batch of nothing but blanks changes nothing and is refused`(json: String) throws {
    let refused = try #require(try refusal(of: json))

    #expect(refused.message.contains("a batch is a mapping"))
  }

  @Test(arguments: [
    #"{"remove": "app.dark.x"}"#,
    #"{"remove": {}}"#,
    #"{"remove": [1]}"#,
    #"{"remove": [["app.dark.x"]]}"#,
    #"{"remove": ["app.dark.x", {"id": "app.dark.y"}]}"#,
  ])
  func `remove lists use case ids`(json: String) {
    #expect(throws: UseCaseBatchError.removeNotIds(name: "stdin")) {
      try read(json)
    }
  }

  @Test(arguments: [
    #"{"save": "app.dark.x"}"#,
    #"{"save": {"id": "app.dark.x"}}"#,
  ])
  func `save lists whole use cases`(json: String) {
    #expect(throws: UseCaseBatchError.saveNotUseCases(name: "stdin")) {
      try read(json)
    }
  }

  @Test
  func `a save that is not a use case says which one`() {
    #expect(throws: UseCaseBatchError.editing(.notAUseCase(name: "stdin save[1]"))) {
      try read(#"{"save": [{"id": "app.dark.a", "title": "A"}, {"title": "no id"}]}"#)
    }
    #expect(throws: UseCaseBatchError.editing(.notAUseCase(name: "stdin save[0]"))) {
      try read(#"{"save": ["app.dark.a"]}"#)
    }
  }

  @Test
  func `a save that breaks a rule of a use case file is invalid, with the problems`() throws {
    let refused = try #require(
      try refusal(of: #"{"save": [{"id": "app.dark.a", "title": "A", "runner": "swift"}]}"#),
    )

    #expect(refused.kind == .invalid)
    #expect(refused.message.contains("runner"))
  }

  @Test
  func `input that cannot be read is told as it was`() {
    let reader = UseCaseBatchReader(
      reader: MockAuthoredInput(failing: .notAFile(path: "missing.yml")),
      checker: UseCaseInputChecker(),
    )

    #expect(throws: UseCaseBatchError.input(message: "'missing.yml' is not a file")) {
      try reader.read("missing.yml")
    }
  }
}
