import Testing
@testable import UseCasesCore

struct StringSearchWordsTests {
  @Test(arguments: [
    ("double tap", ["double", "tap"]),
    ("Double-Tap", ["double", "tap"]),
    ("  spaced   out  ", ["spaced", "out"]),
    ("area07.rule05", ["area07", "rule05"]),
    ("it's", ["it", "s"]),
    ("Ünïcode ÉCOLE", ["ünïcode", "école"]),
    ("", []),
    ("--- !!", []),
    ("日本語 テスト", ["日本語", "テスト"]),
  ])
  func `a word is a run of letters and digits, in lower case`(
    text: String,
    expected: [String],
  ) {
    #expect(text.searchWords == expected)
  }

  @Test
  func `a letter with a combining accent stays one word`() {
    #expect("cafe\u{301} au lait".searchWords == ["cafe\u{301}", "au", "lait"])
  }
}
