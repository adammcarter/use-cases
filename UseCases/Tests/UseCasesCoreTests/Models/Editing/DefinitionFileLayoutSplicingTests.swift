import Testing
@testable import UseCasesCore

struct DefinitionFileLayoutSplicingTests {
  private static let three = """
  # top
  use_cases:
    - id: a
      title: A

    # about b
    - id: b
      title: B

    - id: c
      title: C
  """

  private func layout(_ text: String) throws -> DefinitionFileLayout {
    try DefinitionFileLayout(text: text)
  }

  @Test
  func `replacing one use case leaves every other line where it was`() throws {
    let layout = try layout(Self.three)

    let lines = layout.replacing(
      1,
      with: ["  - id: b", "    title: Changed", "    intent: more"],
    )

    #expect(lines == [
      "# top", "use_cases:", "  - id: a", "    title: A", "",
      "  # about b",
      "  - id: b", "    title: Changed", "    intent: more", "",
      "  - id: c", "    title: C",
    ])
  }

  @Test
  func `a replacement that ends in blank lines of its own takes the place of the gap`() throws {
    let layout = try layout(Self.three)

    let lines = layout.replacing(
      0,
      with: ["  - id: a", "    intent: |+", "      text", ""],
    )

    #expect(lines.prefix(6) == [
      "# top", "use_cases:", "  - id: a", "    intent: |+", "      text", "",
    ])
    #expect(lines[6] == "  # about b")
  }

  @Test
  func `a block that kept its blank lines leaves them as the gap when it is replaced by plain text`(
  ) throws {
    let layout = try layout(
      "use_cases:\n  - id: a\n    intent: |+\n      text\n\n  - id: b\n    title: B\n",
    )

    let lines = layout.replacing(
      0,
      with: ["  - id: a", "    title: A"],
    )

    #expect(lines == ["use_cases:", "  - id: a", "    title: A", "", "  - id: b", "    title: B"])
  }

  @Test
  func `removing a middle use case takes its comment and blank lines, and nothing else`() throws {
    let layout = try layout(Self.three)

    #expect(layout.removing(1) == [
      "# top", "use_cases:", "  - id: a", "    title: A", "",
      "  - id: c", "    title: C",
    ])
  }

  @Test
  func `removing the first use case leaves the ones after it`() throws {
    let layout = try layout(Self.three)

    #expect(layout.removing(0).prefix(4) == ["# top", "use_cases:", "  # about b", "  - id: b"])
  }

  @Test
  func `removing the last use case takes the gap before it, so no blank line is left behind`(
  ) throws {
    let layout = try layout(Self.three)

    #expect(layout.removing(2) == [
      "# top", "use_cases:", "  - id: a", "    title: A", "",
      "  # about b",
      "  - id: b", "    title: B",
    ])
  }

  @Test
  func `removing the last use case keeps what the file had after it`() throws {
    let layout =
      try layout("use_cases:\n  - id: a\n    title: A\n\n  - id: b\n    title: B\n\nprefix: x\n")

    #expect(layout.removing(1) == ["use_cases:", "  - id: a", "    title: A", "", "prefix: x"])
  }

  @Test
  func `a use case is added after the last one, set apart as the file sets its use cases apart`(
  ) throws {
    let layout = try layout(Self.three)

    #expect(layout.appending(["  - id: d", "    title: D"]).suffix(4) == [
      "    title: C", "", "  - id: d", "    title: D",
    ])
  }

  @Test
  func `a file with one use case gets the next one right under it`() throws {
    let layout = try layout("prefix: a\nuse_cases:\n  - id: a\n    title: A\n")

    #expect(layout.appending(["  - id: b", "    title: B"]) == [
      "prefix: a", "use_cases:", "  - id: a", "    title: A", "  - id: b", "    title: B",
    ])
  }

  @Test
  func `nothing is put between a block that keeps its blank lines and the next use case`() throws {
    let layout = try layout(
      "use_cases:\n  - id: a\n    title: A\n\n  - id: b\n    intent: |+\n      text\n\n",
    )

    #expect(layout.appending(["  - id: c", "    title: C"]) == [
      "use_cases:", "  - id: a", "    title: A", "", "  - id: b", "    intent: |+", "      text",
      "",
      "  - id: c", "    title: C",
    ])
  }

  @Test
  func `what follows the last use case stays after the one that is added`() throws {
    let layout = try layout("use_cases:\n  - id: a\n    title: A\n# end\n")

    #expect(layout.appending(["  - id: b", "    title: B"]) == [
      "use_cases:", "  - id: a", "    title: A", "  - id: b", "    title: B", "# end",
    ])
  }

  @Test
  func `removing the first use case takes the comment above it and leaves the header`() throws {
    let layout = try layout("# top\nuse_cases:\n  # first\n  - id: a\n    title: A\n  - id: b\n")

    #expect(layout.items[0].attachedStart == 2)
    #expect(layout.removing(0) == ["# top", "use_cases:", "  - id: b"])
  }

  @Test
  func `replacing a use case keeps the comment above it`() throws {
    let layout = try layout("use_cases:\n  # first\n  - id: a\n    title: A\n")

    #expect(layout.replacing(0, with: ["  - id: a", "    title: B"]) == [
      "use_cases:", "  # first", "  - id: a", "    title: B",
    ])
  }

  @Test
  func `a comment with a blank line below it stays when the use case before goes`() throws {
    let layout = try layout("use_cases:\n  - id: a\n    title: A\n  # alone\n\n  - id: b\n")

    #expect(layout.removing(0) == ["use_cases:", "  # alone", "", "  - id: b"])
  }
}
