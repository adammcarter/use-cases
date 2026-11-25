import Testing
@testable import UseCasesTransformers

struct LinkBlockTests {
  private let lines = [
    "test('a', () => {",
    "  if (x) {",
    "    go()",
    "  }",
    "})",
    "next()",
  ]

  @Test
  func `line is the matching line only`() {
    #expect(LinkBlock.line.lastLine(
      in: lines,
      from: 0,
      column: 0,
    ) == 0)
  }

  @Test
  func `braces reach the brace that closes the first one`() {
    #expect(LinkBlock.braces.lastLine(
      in: lines,
      from: 0,
      column: 0,
    ) == 4)
  }

  @Test
  func `braces count from the match, not from the start of its line`() {
    let lines = [
      "{ unrelated } test('a') {",
      "  body()",
      "}",
    ]

    #expect(LinkBlock.braces.lastLine(
      in: lines,
      from: 0,
      column: 14,
    ) == 2)
  }

  @Test
  func `a block that opens and closes on one line ends there`() {
    let lines = [
      "test('a', () => { ok })",
      "x",
    ]

    #expect(LinkBlock.braces.lastLine(
      in: lines,
      from: 0,
      column: 0,
    ) == 0)
  }

  @Test
  func `no brace, or one that never closes, leaves the matching line`() {
    let none = [
      "test('a')",
      "x",
    ]
    let unclosed = [
      "test('a') {",
      "x",
    ]

    #expect(LinkBlock.braces.lastLine(
      in: none,
      from: 0,
      column: 0,
    ) == 0)
    #expect(LinkBlock.braces.lastLine(
      in: unclosed,
      from: 0,
      column: 0,
    ) == 0)
  }

  @Test
  func `a closing brace before the first opening one is not a block`() {
    let lines = [
      "} test('a') {",
      "}",
    ]

    #expect(LinkBlock.braces.lastLine(
      in: lines,
      from: 0,
      column: 0,
    ) == 1)
  }

  @Test
  func `braces inside a test name end the block early, as the catalogue warns`() {
    let lines = [
      "test('a{b}c', () => {",
      "  body()",
      "})",
    ]

    #expect(LinkBlock.braces.lastLine(
      in: lines,
      from: 0,
      column: 0,
    ) == 0)
  }
}
