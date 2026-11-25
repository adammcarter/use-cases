import Testing
@testable import UseCasesCore

struct YAMLNestingScannerTests {
  private let scanner = YAMLNestingScanner()

  @Test(arguments: [
    ("[[[[x]]]]", 3, 1),
    ("[[[x]]]", 3, nil),
    ("{a: {b: {c: {d: 1}}}}", 3, 1),
    ("{a: {b: {c: 1}}}", 3, nil),
    ("a:\n  b:\n    c:\n      d: 1\n", 3, 4),
    ("a:\n  b:\n    c: 1\n", 3, nil),
    ("- - - - x", 3, 1),
    ("- - - x", 3, nil),
    ("-\n  -\n    -\n      - x\n", 3, 4),
    ("a:\n- b:\n  - c:\n    - d\n", 5, 4),
    ("a:\n- b:\n  - c:\n    - d\n", 6, nil),
    ("a: [[[x]]]\n", 3, 1),
    ("a: [[x]]\n", 3, nil),
    ("a:\n  b: [[[x]]]\n", 3, 2),
    ("[\n[\n[\n[\n]]]]", 3, 4),
    ("- a: [x]\n- b: {c: [d]}\n", 4, nil),
    ("a: &x\n  b: &y\n    c: &z\n      d: 1\n", 3, 4),
    ("a:\n  b: 1\n  c: 2\nd:\n  e: 3\n", 2, nil),
    ("a:\n  b:\n    c: 1\nd:\n  e:\n    f: 2\n", 3, nil),
    ("", 1, nil),
    ("x", 1, nil),
  ])
  func `the first line past the limit is found`(
    text: String,
    limit: Int,
    line: Int?,
  ) {
    #expect(scanner.firstLine(deeperThan: limit, in: YAMLSourceText(text)) == line)
  }

  @Test(arguments: [
    "title: \"[[[[[[\"\n",
    "title: '[[[[[[ it''s [['\n",
    "title: a [[[[ b\n",
    "title: [ok, \"[[[[[[\", 'x [[[']\n",
    "a: 1 # [[[[[[\n",
    "# [[[[[[\na: 1\n",
    "a: |\n  [[[[[[\n  - - - -\n  b: c\nz: 1\n",
    "a: >\n  [[[[[[\n\n  - - - -\nz: 1\n",
    "a: \"x\n  [[[[[[\n  y\"\nb: 1\n",
    "---\na:\n  b:\n---\na:\n  b:\n",
    "[don't, [x], y]\n",
    "- http://example.com/a:b\n",
    "key: value with: colons\n",
  ])
  func `brackets and indentation that are text do not count`(text: String) {
    #expect(scanner.firstLine(deeperThan: 2, in: YAMLSourceText(text)) == nil)
  }

  @Test
  func `five thousand levels are found without recursion`() {
    let flow = String(repeating: "[", count: 5000)
    var block = ""

    for level in 0 ..< 5000 {
      block += String(repeating: " ", count: level) + "a:\n"
    }

    #expect(scanner.firstLine(deeperThan: 64, in: YAMLSourceText(flow)) == 1)
    #expect(scanner.firstLine(deeperThan: 64, in: YAMLSourceText(block)) == 65)
  }
}
