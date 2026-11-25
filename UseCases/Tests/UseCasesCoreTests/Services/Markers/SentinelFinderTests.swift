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
    SentinelSample("\(MarkerText.sentinel)a#b", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)end a#b", .end, "a#b"),
    SentinelSample("\(MarkerText.sentinel)end\ta#b", .end, "a#b"),
    SentinelSample("\(MarkerText.sentinel)end \t  a#b", .end, "a#b"),
    SentinelSample("\(MarkerText.sentinel)end   ", .end, ""),
    SentinelSample("\(MarkerText.sentinel)endpoint#x", .start, "endpoint#x"),
    SentinelSample("\(MarkerText.sentinel)end-a#b", .start, "end-a#b"),
    SentinelSample("\(MarkerText.sentinel)end", .start, "end"),
    SentinelSample("\(MarkerText.sentinel)end\na#b", .start, "end"),
    SentinelSample("\(MarkerText.sentinel)end\r\n", .start, "end"),
    SentinelSample(MarkerText.sentinel, .start, ""),
    SentinelSample("\(MarkerText.sentinel) a#b", .start, ""),
    SentinelSample("\(MarkerText.sentinel)App.login#x", .start, ""),
    SentinelSample("\(MarkerText.sentinel)app.Login#x", .start, "app"),
    SentinelSample("// \(MarkerText.sentinel)app.login#submit", .start, "app.login#submit"),
    SentinelSample("# \(MarkerText.sentinel)app.login#submit", .start, "app.login#submit"),
    SentinelSample("^^^ \(MarkerText.sentinel)app.login#submit ^^^", .start, "app.login#submit"),
    SentinelSample("REM \(MarkerText.sentinel)app.login#submit", .start, "app.login#submit"),
    SentinelSample("<!--\(MarkerText.sentinel)a#b-->", .start, "a#b"),
    SentinelSample("/*\(MarkerText.sentinel)a#b*/", .start, "a#b"),
    SentinelSample("\"# \(MarkerText.sentinel)a#b\\n\",", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#b.", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#b-.-", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#b.c-", .start, "a#b.c"),
    SentinelSample("\(MarkerText.sentinel)a#b\u{A0}note", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#bFoo", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#b@x", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#b_c", .start, "a#b"),
    SentinelSample("\(MarkerText.sentinel)a#", .start, "a#"),
    SentinelSample("\(MarkerText.sentinel)---", .start, ""),
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
      ("\(MarkerText.sentinel)a.b#submiT", "T"),
      ("\(MarkerText.sentinel)a.b#c_d", "_d"),
      ("\(MarkerText.sentinel)a#bFoo", "Foo"),
      ("\(MarkerText.sentinel)BAD", "BAD"),
      ("\(MarkerText.sentinel)a#b-A", "A"),
      ("\(MarkerText.sentinel)a#b.", ""),
      ("\(MarkerText.sentinel)a#b_", "_"),
      ("\(MarkerText.sentinel)a#b-->", ""),
      ("\(MarkerText.sentinel)a#b*/", ""),
      ("\(MarkerText.sentinel)a#b\u{A0}note", ""),
      ("\(MarkerText.sentinel)a#b é", ""),
      ("\(MarkerText.sentinel)a#b\(MarkerText.sentinel)end a#b", ""),
      (MarkerText.sentinel, ""),
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
      ("\(MarkerText.sentinel)a.b#submiT", 0 ..< 20),
      ("\(MarkerText.sentinel)a.b#c_d", 0 ..< 17),
      ("\(MarkerText.sentinel)a#b-A", 0 ..< 15),
      ("\(MarkerText.sentinel)BAD", 0 ..< 13),
      ("\(MarkerText.sentinel)end a#bZ", 0 ..< 18),
      ("\(MarkerText.sentinel)a#b-->", 0 ..< 13),
      ("\(MarkerText.sentinel)a#b\u{A0}x", 0 ..< 13),
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
    let text = "\(MarkerText.sentinel)a#b" + String(repeating: "Z", count: 100)
    let sentinel = try #require(find(text).first)

    #expect(sentinel.tokenRange == 0 ..< 113)
    #expect(sentinel.followingWord.count == 40)
  }

  @Test
  func `scanning goes on after the word`() {
    let found = find("\(MarkerText.sentinel)a#bZZ \(MarkerText.sentinel)c#d")

    #expect(found.map(\.identifier) == ["a#b", "c#d"])
    #expect(found.map(\.tokenRange) == [0 ..< 15, 16 ..< 29])
  }

  @Test
  func `the word after an id run is cut at forty characters`() throws {
    let text = "\(MarkerText.sentinel)a#b" + String(repeating: "Z", count: 100)
    let sentinel = try #require(find(text).first)

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
    let found = find("x \(MarkerText.sentinel)end  a#b-- y")

    let sentinel = try #require(found.first)
    #expect(sentinel.tokenRange == 2 ..< 20)
  }

  @Test
  func `one sentinel directly after another is judged on its own`() {
    let found = find("\(MarkerText.sentinel)\(MarkerText.sentinel)a#b")

    #expect(found.map(\.identifier) == ["", "a#b"])
    #expect(found.map(\.tokenRange) == [0 ..< 10, 10 ..< 23])
  }

  @Test
  func `an end sentinel with nothing after its separator leaves the next sentinel alone`() {
    let found = find("\(MarkerText.sentinel)end \(MarkerText.sentinel)a#b")

    #expect(found.map(\.kind) == [.end, .start])
    #expect(found.map(\.identifier) == ["", "a#b"])
  }

  @Test
  func `every sentinel on a line is found, each with its line`() {
    let found = find(
      "\(MarkerText.sentinel)a#b\r\nx\n\(MarkerText.sentinel)end a#b \(MarkerText.sentinel)c#d\r"
        + "\(MarkerText.sentinel)e#f",
    )

    #expect(found.map(\.identifier) == ["a#b", "a#b", "c#d", "e#f"])
    #expect(found.map(\.line) == [1, 3, 3, 4])
  }

  @Test
  func `a sentinel is found after text in any script`() {
    let found = find("日本語 café \(MarkerText.sentinel)a#b")

    #expect(found.map(\.identifier) == ["a#b"])
    #expect(found.first?.tokenRange == 16 ..< 29)
  }

  @Test
  func `a file is checked for the sentinel without being read as text`() {
    let bytes: [UInt8] = [0xFF, 0xC0, 0x80] + Array("\(MarkerText.sentinel)a#b".utf8) + [0xE9]

    #expect(finder.holdsSentinel(bytes))
  }
}
