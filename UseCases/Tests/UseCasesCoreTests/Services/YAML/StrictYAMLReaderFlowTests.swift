import Testing
@testable import UseCasesCore

struct StrictYAMLReaderFlowTests {
  private let reader = StrictYAMLReader()

  // Mutant: the check removed, or made to apply to block text too.
  @Test(arguments: [
    "when: [x?]\n",
    "when: [Is the total zero?]\n",
    "when: [a, b?]\n",
    "when: {a: x?}\n",
    "when: {x?: 1}\n",
    "when: [[x?]]\n",
    "when: {a: [x?]}\n",
    "- when: [x?]\n",
    "a:\n  b: [ok, y?]\n",
  ])
  func `a plain text with a question mark in a list or mapping on one line is refused`(
    text: String,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    guard case let .unquoted(_, found, problem) = error else {
      Issue.record("not an unquoted refusal: \(error)")
      return
    }

    #expect(problem == .questionMarkInFlow)
    #expect(found.contains("?"))
    #expect(error.message.contains("quote it"))
    #expect(error.message.contains("'?'"))
  }

  @Test
  func `the refusal says where`() throws {
    let error = try #require(reader.attempt("a: 1\nwhen: [x?]\n", file: "use-cases/a.yml").failure)

    #expect(error.message.hasPrefix("use-cases/a.yml:2: 'x?' has a '?' in a list or mapping"))
  }

  @Test(arguments: [
    "when: [\"x?\"]\n",
    "when: ['x?']\n",
    "when: {a: \"x?\"}\n",
    "when: [\"Is the total zero?\", y]\n",
  ])
  func `the same text in quotes is read`(text: String) {
    #expect(reader.attempt(text).success != nil)
  }

  @Test(arguments: [
    "when: Is the total zero?\n",
    "when:\n  - Is the total zero?\n  - x?\n",
    "when:\n  a: Is it?\n",
    "when: |\n  Is it?\n",
    "when: >\n  Is it?\n",
    "when: [a, b]\nthen: Is it?\n",
  ])
  func `a question mark in text outside a list or mapping on one line is read`(text: String) {
    #expect(reader.attempt(text).success != nil)
  }

  @Test
  func `a list on one line inside a block, and text after it, are told apart`() throws {
    let value = try #require(reader.attempt("a: [x]\nb: y?\n").success)

    #expect(value == .members(["a": .array([.string("x")]), "b": .string("y?")]))
  }

  @Test
  func `a settings file keeps the same rule, since it is about what readers disagree on`() throws {
    let error = try #require(reader.attempt("when: [x?]\n", kind: .settings).failure)

    #expect(error.message.contains("quote it"))
  }
}
