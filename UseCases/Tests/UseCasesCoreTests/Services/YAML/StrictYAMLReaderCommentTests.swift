import Testing
@testable import UseCasesCore

struct StrictYAMLReaderCommentTests {
  private let reader = StrictYAMLReader()

  @Test
  func `the pinned example is refused with the file, the line and both texts`() throws {
    let text = """
    prefix: dark
    use_cases:
      - id: toggle
        title: Dark mode
        value_tier: core
        intent: Readable at night.
        scenarios:
          - id: on-state
            when: [x]
            then: [y]
        validation:
          - id: manual
            type: { kind: acceptance }
            covers: [on-state]
            procedure:
              steps:
                - Check medal #4 shows
    """

    let error = try #require(reader.attempt(text).failure)

    #expect(error.message.contains("use-cases/a.yml:17: 'Check medal' is followed by '#4 shows'"))
    #expect(error.message.contains("quote the whole text"))
  }

  @Test(arguments: [
    ("title: Dark mode # note\n", "Dark mode", "# note", 1),
    ("- Check medal #4 shows\n", "Check medal", "#4 shows", 1),
    ("title: High contrast   # for low vision\n", "High contrast", "# for low vision", 1),
    ("title: High contrast\t# tab first\n", "High contrast", "# tab first", 1),
    ("title: a # one # two\n", "a", "# one # two", 1),
    ("title: a #\n", "a", "#", 1),
    ("count: 3 # three\n", "3", "# three", 1),
    ("done: true # yes\n", "true", "# yes", 1),
    ("a: [x, y # c\n]\n", "y", "# c", 1),
    ("a: {k: v # c\n}\n", "v", "# c", 1),
    ("a:\n  - one\n    two # c\n", "one two", "# c", 3),
    ("a:\n  - one\n\n    two # c\n", "one\ntwo", "# c", 4),
    ("Dark mode # note\n", "Dark mode", "# note", 1),
    ("title # note: x\n", "title", "# note: x", 1),
    ("x: 1\ny: &anchor value # c\n", "value", "# c", 2),
    ("title: Dark mode # note", "Dark mode", "# note", 1),
    ("title: Dark mode # note\r\nnext: 1\r\n", "Dark mode", "# note", 1),
    ("a: x\nb: y   # c\nc: z\n", "y", "# c", 2),
  ])
  func `unquoted text followed by a comment is refused in a use case file`(
    text: String,
    scalar: String,
    comment: String,
    line: Int,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    #expect(error == .textCutByComment(
      YAMLLocation(file: "use-cases/a.yml", line: line),
      text: scalar,
      comment: comment,
    ))
    #expect(error.message
      .contains("'\(scalar.replacing("\n", with: " "))' is followed by '\(comment)'"))
    #expect(error.message.contains("quote the whole text"))
    #expect(error.message.contains("on its own line"))
  }

  @Test
  func `a plain key followed by a comment is refused too`() throws {
    let error = try #require(reader.attempt("title # a note\n").failure)

    guard case .textCutByComment = error else {
      Issue.record("refused as \(error)")
      return
    }
  }

  @Test(arguments: [
    "title: \"Dark mode #2\"\n",
    "title: 'Dark mode #2'\n",
    "title: 'Dark mode' # note after quoted text\n",
    "title: \"Dark mode\"  # note after quoted text\n",
    "\"title\": 'Dark mode' # note\n",
    "# own line\ntitle: Dark mode\n",
    "title: Dark mode\n# own line\nother: x\n",
    "title: Dark mode\n  # indented own line\nother: x\n",
    "title: a#b\n",
    "steps: # note after the key\n  - one\n",
    "steps:\n  - one\n  # between\n  - two\n",
    "text: |\n  Check #4 shows\n",
    "text: >\n  Check #4 shows\n",
    "text: | # note on the header\n  Check #4 shows\n",
    "a: [x, y] # after the list\n",
    "a: {k: v}  # after the mapping\n",
    "a: # nothing here\n",
    "- # empty item\n  - x\n",
    "a: b#c\n",
  ])
  func `quoted text, comments on their own line and the rest are fine`(text: String) {
    let result = reader.attempt(text)

    #expect(result.failure == nil)
  }

  @Test(arguments: [
    "title: Dark mode # note\n",
    "a:\n  - one # note\n",
    "count: 3 # three\n",
    "a: [x, y # c\n]\n",
  ])
  func `a settings file keeps its end-of-line comments`(text: String) {
    #expect(reader.attempt(text, kind: .settings).success != nil)
  }

  @Test
  func `a settings file reads the text before the comment`() {
    let result = reader.attempt(
      "prefix: app   # the namespace\nroot: true # yes\n",
      kind: .settings,
    )

    #expect(result.success == .members(["prefix": .string("app"), "root": .boolean(true)]))
  }

  @Test
  func `a comment after quoted text reads the quoted text`() {
    let result = reader.attempt("title: \"Dark mode\"  # note\nother: 'x' # y\n")

    #expect(result.success == .members(["title": .string("Dark mode"), "other": .string("x")]))
  }

  @Test
  func `a hash inside a quoted or block scalar is text`() {
    let result = reader.attempt("a: \"x #1\"\nb: |\n  y #2\n")

    #expect(result.success == .members(["a": .string("x #1"), "b": .string("y #2\n")]))
  }

  @Test
  func `multi-byte text before a comment is found at the right place`() {
    let error = reader.attempt("title: caf\u{E9} \u{1F600} # note\n").failure

    #expect(error?.message.contains("'caf\u{E9} \u{1F600}' is followed by '# note'") == true)
  }

  @Test(arguments: [
    "title: &x # c\n  Dark mode\n",
    "title: &x\n  # c\n  Dark mode\n",
    "title: &x   # c\n\n  # d\n  Dark mode\n",
    "title: &x # c\r\n  Dark mode\r\n",
  ])
  func `an anchor followed by a comment before its text reads the text`(text: String) {
    #expect(reader.attempt(text).success == .members(["title": .string("Dark mode")]))
  }

  @Test
  func `a comment after text that follows an anchor and a comment is still refused`() {
    let error = reader.attempt("title: &x # c\n  Dark mode # note\n").failure

    #expect(error == .textCutByComment(
      YAMLLocation(file: "use-cases/a.yml", line: 2),
      text: "Dark mode",
      comment: "# note",
    ))
  }

  @Test
  func `an anchored value with comments around it can be aliased`() {
    let result = reader.attempt("a: &x # c\n  Dark mode\nb: *x\n")

    #expect(result.success == .members(["a": .string("Dark mode"), "b": .string("Dark mode")]))
  }
}
