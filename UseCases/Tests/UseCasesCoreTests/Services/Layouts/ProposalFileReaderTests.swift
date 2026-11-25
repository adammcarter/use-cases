import Foundation
import Testing
@testable import UseCasesCore

struct ProposalFileReaderTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  private static let whole = """
  {"title": " Lock accounts ", "remove": ["app.solo.only"],
   "save": [{"id": "app.dark.toggle", "title": "Dark mode, changed"}],
   "untouched": ["app.dark.other"], "fits": {"app.dark.toggle": "extends"},
   "you_see": {"app.dark.toggle": " a moon "},
   "decisions": [{"question": " how long ", "options": [" a ", "b"]}],
   "golden": {"app.dark.toggle": ["on-state"]}}
  """

  private func refusal(of json: String) throws -> LayoutRenderingError? {
    do {
      _ = try fixture.proposal(json)

      return nil
    } catch let error as LayoutRenderingError {
      return error
    }
  }

  @Test
  func `the proposal and the batch inside it come from one reading of the input`() throws {
    let file = try fixture.proposal(Self.whole)

    #expect(file.name == "stdin")
    #expect(file.title == "Lock accounts")
    #expect(file.batch.removals == ["app.solo.only"])
    #expect(file.batch.saves.map(\.identifier.text) == ["app.dark.toggle"])
    #expect(file.untouched == ["app.dark.other"])
    #expect(file.fits == ["app.dark.toggle": .extends])
    #expect(file.youSee == ["app.dark.toggle": "a moon"])
    #expect(file.decisions == [ProposalDecision(question: "how long", options: ["a", "b"])])
    #expect(file.golden == ["app.dark.toggle": ["on-state"]])
  }

  @Test
  func `the keys beside the batch are all optional but the title`() throws {
    let file = try fixture.proposal(
      #"{"title": "T", "remove": ["app.solo.only"]}"#,
    )

    #expect(file.untouched.isEmpty)
    #expect(file.fits.isEmpty)
    #expect(file.youSee.isEmpty)
    #expect(file.decisions.isEmpty)
    #expect(file.golden.isEmpty)
  }

  @Test
  func `a key a proposal does not have is named before the batch is looked at`() throws {
    let refused = try #require(
      try refusal(of: #"{"title": "T", "colour": "blue", "shade": 1}"#),
    )

    #expect(refused.kind == .usage)
    #expect(refused.message.contains("a proposal has remove, save, title"))
    #expect(refused.message.hasSuffix("unknown: colour, shade"))
  }

  @Test(arguments: [
    (#"{"remove": ["app.solo.only"]}"#, "has a `title`"),
    (#"{"title": "", "remove": ["app.solo.only"]}"#, "has a `title`"),
    (#"{"title": " \n", "remove": ["app.solo.only"]}"#, "has a `title`"),
    (#"{"title": 3, "remove": ["app.solo.only"]}"#, "has a `title`"),
    (#"{"title": "T", "remove": ["a.b.c"], "untouched": "app.dark.other"}"#, "`untouched` lists"),
    (#"{"title": "T", "remove": ["a.b.c"], "untouched": [1]}"#, "`untouched` lists"),
    (#"{"title": "T", "remove": ["a.b.c"], "fits": []}"#, "`fits` maps"),
    (#"{"title": "T", "remove": ["a.b.c"], "fits": {"a.b.c": "new"}}"#, "extends or changes"),
    (#"{"title": "T", "remove": ["a.b.c"], "fits": {"a.b.c": "replaces"}}"#, "extends or changes"),
    (#"{"title": "T", "remove": ["a.b.c"], "fits": {"a.b.c": 3}}"#, "extends or changes"),
    (#"{"title": "T", "remove": ["a.b.c"], "you_see": "x"}"#, "`you_see` maps"),
    (#"{"title": "T", "remove": ["a.b.c"], "you_see": {"a.b.c": ""}}"#, "`you_see` for a.b.c"),
    (#"{"title": "T", "remove": ["a.b.c"], "you_see": {"a.b.c": 1}}"#, "`you_see` for a.b.c"),
    (#"{"title": "T", "remove": ["a.b.c"], "decisions": {}}"#, "`decisions` is a list"),
    (#"{"title": "T", "remove": ["a.b.c"], "decisions": ["q"]}"#, "at least two `options`"),
    (
      #"{"title": "T", "remove": ["a.b.c"], "decisions": [{"question": "q"}]}"#,
      "at least two `options`",
    ),
    (
      #"{"title": "T", "remove": ["a.b.c"], "decisions": [{"question": "q", "options": ["a"]}]}"#,
      "at least two `options`",
    ),
    (
      #"{"title": "T", "remove": ["a.b.c"], "decisions": [{"question": "q", "options": []}]}"#,
      "at least two `options`",
    ),
    (
      #"{"title":"T","remove":["a.b.c"],"decisions":[{"question":"q","options":["a",""]}]}"#,
      "at least two `options`",
    ),
    (
      #"{"title":"T","remove":["a.b.c"],"decisions":[{"question":"","options":["a","b"]}]}"#,
      "a `question`",
    ),
    (
      #"{"title":"T","remove":["a.b.c"],"decisions":[{"question":"q","options":["a","b"],"x":1}]}"#,
      "and nothing else",
    ),
    (#"{"title": "T", "remove": ["a.b.c"], "golden": {"a.b.c": "s"}}"#, "`golden` for a.b.c"),
    (#"{"title": "T", "remove": ["a.b.c"], "golden": {"a.b.c": [1]}}"#, "`golden` for a.b.c"),
    (#"{"title": "T", "remove": ["a.b.c"], "golden": []}"#, "`golden` maps"),
  ])
  func `a key of the wrong shape is refused in words that name it`(
    json: String,
    message: String,
  ) throws {
    let refused = try #require(try refusal(of: json))

    #expect(refused.kind == .usage)
    #expect(refused.message.contains(message))
  }

  @Test
  func `the batch inside is held to what apply holds a batch to`() throws {
    #expect(
      try refusal(of: #"{"title": "T"}"#)
        == .batch(.notABatch(name: "stdin", problem: "this one changes nothing")),
    )
    #expect(try refusal(of: #"{"title": "T", "save": [{"id": "app.dark.a"}]}"#)?.kind == .invalid)
    #expect(
      try refusal(of: #"{"title": "T", "save": ["app.dark.a"]}"#)
        == .batch(.editing(.notAUseCase(name: "stdin save[0]"))),
    )
    #expect(try refusal(of: "[1]") == .batch(.notABatch(name: "stdin", problem: nil)))
  }

  @Test
  func `a use case in the batch twice is refused, removing and saving it included`() throws {
    let refused = try refusal(
      of: """
      {"title": "T", "remove": ["app.dark.toggle"],
       "save": [{"id": "app.dark.toggle", "title": "Dark mode"}]}
      """,
    )

    #expect(refused == .batch(.repeated(identifier: "app.dark.toggle")))
  }

  @Test
  func `an id listed untouched twice is refused as usage`() throws {
    let refused = try #require(
      try refusal(
        of: """
        {"title": "T", "remove": ["a.b.c"], "untouched": ["app.dark.other", "app.dark.other"]}
        """,
      ),
    )

    #expect(refused.kind == .usage)
    #expect(refused.message.hasSuffix("`untouched` lists 'app.dark.other' more than once"))
  }

  @Test(arguments: [
    ("\u{1B}[8m", "\\x1B"),
    ("\u{7}", "\\x07"),
    ("\u{0}", "\\x00"),
    ("\u{7F}", "\\x7F"),
    ("\u{9B}", "\\x9B"),
    ("\u{85}x\u{80}", "\\x80"),
    ("\u{202E}", "\\u202E"),
    ("\u{2066}", "\\u2066"),
    ("\u{2069}", "\\u2069"),
  ])
  func `a control character in a text of the proposal is refused, naming the field`(
    control: String,
    spelled: String,
  ) throws {
    let text = "a\(control)b"
    let fields: [(String, [String: Any])] = [
      ("title", ["title": text, "remove": ["a.b.c"]]),
      ("you_see for a.b.c", ["title": "T", "remove": ["a.b.c"], "you_see": ["a.b.c": text]]),
      (
        "decisions question",
        [
          "title": "T",
          "remove": ["a.b.c"],
          "decisions": [["question": text, "options": ["a", "b"]]],
        ],
      ),
      (
        "decisions options",
        [
          "title": "T",
          "remove": ["a.b.c"],
          "decisions": [["question": "q", "options": ["a", text]]],
        ],
      ),
    ]

    for (field, object) in fields {
      let data = try JSONSerialization.data(withJSONObject: object)
      let json = try #require(String(bytes: data, encoding: .utf8))
      let refused = try #require(try refusal(of: json))

      #expect(refused.kind == .usage)
      #expect(refused.message.contains("`\(field)` holds the control character '\(spelled)'"))
      #expect(!refused.message.unicodeScalars.contains { $0.isTerminalControl })
    }
  }

  @Test
  func `a line break or a tab in a text is fine: a layout collapses it`() throws {
    let file = try fixture.proposal(
      #"{"title": "a\nb\tc", "remove": ["app.solo.only"], "you_see": {"app.solo.only": "x\ry"}}"#,
    )

    #expect(file.title == "a\nb\tc")
  }

  @Test
  func `input that cannot be read is told as it was`() {
    let reader = ProposalFileReader(
      reader: MockAuthoredInput(failing: .notAFile(path: "missing.yml")),
      batches: UseCaseBatchReader(
        reader: MockAuthoredInput(failing: .notAFile(path: "missing.yml")),
        checker: UseCaseInputChecker(),
      ),
    )

    #expect(throws: LayoutRenderingError.input(message: "'missing.yml' is not a file")) {
      try reader.read("missing.yml")
    }
  }
}
