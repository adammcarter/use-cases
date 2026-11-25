import Testing
@testable import UseCasesCore

struct SentinelFinderTests {
  private let finder = SentinelFinder()

  private func find(_ text: String) -> [MarkerSentinel] {
    let bytes = Array(text.utf8)

    return finder.sentinels(
      in: bytes,
      lines: LineIndex(bytes),
    )
  }

  private static let samples = [
    SentinelSample("@use-case:a#b", .start, "a#b"),
    SentinelSample("@use-case:end a#b", .end, "a#b"),
    SentinelSample("@use-case:end\ta#b", .end, "a#b"),
    SentinelSample("@use-case:end \t  a#b", .end, "a#b"),
    SentinelSample("@use-case:end   ", .end, ""),
    SentinelSample("@use-case:endpoint#x", .start, "endpoint#x"),
    SentinelSample("@use-case:end-a#b", .start, "end-a#b"),
    SentinelSample("@use-case:end", .start, "end"),
    SentinelSample("@use-case:end\na#b", .start, "end"),
    SentinelSample("@use-case:end\r\n", .start, "end"),
    SentinelSample("@use-case:", .start, ""),
    SentinelSample("@use-case: a#b", .start, ""),
    SentinelSample("@use-case:App.login#x", .start, ""),
    SentinelSample("@use-case:app.Login#x", .start, "app"),
    SentinelSample("// @use-case:app.login#submit", .start, "app.login#submit"),
    SentinelSample("# @use-case:app.login#submit", .start, "app.login#submit"),
    SentinelSample("^^^ @use-case:app.login#submit ^^^", .start, "app.login#submit"),
    SentinelSample("REM @use-case:app.login#submit", .start, "app.login#submit"),
    SentinelSample("<!--@use-case:a#b-->", .start, "a#b"),
    SentinelSample("/*@use-case:a#b*/", .start, "a#b"),
    SentinelSample("\"# @use-case:a#b\\n\",", .start, "a#b"),
    SentinelSample("@use-case:a#b.", .start, "a#b"),
    SentinelSample("@use-case:a#b-.-", .start, "a#b"),
    SentinelSample("@use-case:a#b.c-", .start, "a#b.c"),
    SentinelSample("@use-case:a#b\u{A0}note", .start, "a#b"),
    SentinelSample("@use-case:a#bFoo", .start, "a#b"),
    SentinelSample("@use-case:a#b@x", .start, "a#b"),
    SentinelSample("@use-case:a#b_c", .start, "a#b"),
    SentinelSample("@use-case:a#", .start, "a#"),
    SentinelSample("@use-case:---", .start, ""),
  ]

  @Test(arguments: Self.samples)
  func `the id is the longest run of id characters, less a trailing hyphen or dot`(
    sample: SentinelSample,
  ) throws {
    let found = find(sample.text)

    let sentinel = try #require(found.first)
    #expect(found.count == 1)
    #expect(sentinel.kind == sample.kind)
    #expect(sentinel.identifier == sample.identifier)
  }

  @Test(
    arguments: [
      ("@use-case:a.b#submiT", "T"),
      ("@use-case:a.b#c_d", "_d"),
      ("@use-case:a#bFoo", "Foo"),
      ("@use-case:BAD", "BAD"),
      ("@use-case:a#b-A", "A"),
      ("@use-case:a#b.", ""),
      ("@use-case:a#b_", "_"),
      ("@use-case:a#b-->", ""),
      ("@use-case:a#b*/", ""),
      ("@use-case:a#b\u{A0}note", ""),
      ("@use-case:a#b é", ""),
      ("@use-case:a#b@use-case:end a#b", ""),
      ("@use-case:", ""),
    ] as [(String, String)],
  )
  func `an id run directly followed by a letter, digit or underscore says what follows`(
    text: String,
    word: String,
  ) throws {
    let sentinel = try #require(find(text).first)

    #expect(sentinel.followingWord == word)
  }

  @Test(
    arguments: [
      ("@use-case:a.b#submiT", 0 ..< 20),
      ("@use-case:a.b#c_d", 0 ..< 17),
      ("@use-case:a#b-A", 0 ..< 15),
      ("@use-case:BAD", 0 ..< 13),
      ("@use-case:end a#bZ", 0 ..< 18),
      ("@use-case:a#b-->", 0 ..< 13),
      ("@use-case:a#b\u{A0}x", 0 ..< 13),
    ] as [(String, Range<Int>)],
  )
  func `a word after an id run is part of the token and a trimmed hyphen or dot is not`(
    text: String,
    token: Range<Int>,
  ) throws {
    let sentinel = try #require(find(text).first)

    #expect(sentinel.tokenRange == token)
  }

  @Test
  func `the whole word is in the token though only forty characters of it are named`() throws {
    let sentinel = try #require(find("@use-case:a#b" + String(repeating: "Z", count: 100)).first)

    #expect(sentinel.tokenRange == 0 ..< 113)
    #expect(sentinel.followingWord.count == 40)
  }

  @Test
  func `scanning goes on after the word`() {
    let found = find("@use-case:a#bZZ @use-case:c#d")

    #expect(found.map(\.identifier) == ["a#b", "c#d"])
    #expect(found.map(\.tokenRange) == [0 ..< 15, 16 ..< 29])
  }

  @Test
  func `the word after an id run is cut at forty characters`() throws {
    let sentinel = try #require(find("@use-case:a#b" + String(repeating: "Z", count: 100)).first)

    #expect(sentinel.followingWord == String(repeating: "Z", count: 40))
  }

  @Test(
    arguments: [
      "", "x", "@use-case", "@use-cas:a#b", "@USE-CASE:a#b", "use-case:a#b", "@use_case:a#b",
    ],
  )
  func `text without the sentinel bytes holds none`(text: String) {
    #expect(find(text).isEmpty)
    #expect(!finder.holdsSentinel(Array(text.utf8)))
  }

  @Test
  func `a token runs from the at sign through the last byte of the id`() throws {
    let found = find("x @use-case:end  a#b-- y")

    let sentinel = try #require(found.first)
    #expect(sentinel.tokenRange == 2 ..< 20)
  }

  @Test
  func `one sentinel directly after another is judged on its own`() {
    let found = find("@use-case:@use-case:a#b")

    #expect(found.map(\.identifier) == ["", "a#b"])
    #expect(found.map(\.tokenRange) == [0 ..< 10, 10 ..< 23])
  }

  @Test
  func `an end sentinel with nothing after its separator leaves the next sentinel alone`() {
    let found = find("@use-case:end @use-case:a#b")

    #expect(found.map(\.kind) == [.end, .start])
    #expect(found.map(\.identifier) == ["", "a#b"])
  }

  @Test
  func `every sentinel on a line is found, each with its line`() {
    let found = find("@use-case:a#b\r\nx\n@use-case:end a#b @use-case:c#d\r@use-case:e#f")

    #expect(found.map(\.identifier) == ["a#b", "a#b", "c#d", "e#f"])
    #expect(found.map(\.line) == [1, 3, 3, 4])
  }

  @Test
  func `a sentinel is found after text in any script`() {
    let found = find("日本語 café @use-case:a#b")

    #expect(found.map(\.identifier) == ["a#b"])
    #expect(found.first?.tokenRange == 16 ..< 29)
  }

  @Test
  func `a file is checked for the sentinel without being read as text`() {
    let bytes: [UInt8] = [0xFF, 0xC0, 0x80] + Array("@use-case:a#b".utf8) + [0xE9]

    #expect(finder.holdsSentinel(bytes))
  }
}
