import Testing
@testable import UseCasesTransformers

struct SourceSearcherTests {
  private func searcher(_ folder: TemporaryFolder) -> SourceSearcher {
    SourceSearcher(
      paths: WorkspacePaths(codeRoot: folder.path),
      reader: ReportFile(),
    )
  }

  @Test
  func `a declaration found once is placed`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.swift",
      "x\nfunc testOne() {}\ny\n",
    )
    var searcher = searcher(folder)

    #expect(
      searcher.find(
        needles: ["func testOne("],
        in: ["a.swift"],
      )
        == .found(
          file: "a.swift",
          line: 2,
        ),
    )
  }

  @Test
  func `a declaration repeated in a file or across files is ambiguous`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.swift",
      "func t() {}\nfunc t() {}\n",
    )
    try folder.write(
      "b.swift",
      "func t() {}\n",
    )
    var searcher = searcher(folder)

    #expect(searcher.find(
      needles: ["func t("],
      in: ["a.swift"],
    ) == .ambiguous(count: 2))
    #expect(searcher.find(
      needles: ["func t("],
      in: ["a.swift", "b.swift"],
    ) == .ambiguous(count: 3))
  }

  @Test
  func `a declaration that is nowhere is missing`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.swift",
      "func other() {}\n",
    )
    var searcher = searcher(folder)

    #expect(searcher.find(
      needles: ["func t("],
      in: ["a.swift"],
    ) == .missing)
    #expect(searcher.find(
      needles: ["func t("],
      in: [],
    ) == .missing)
    #expect(searcher.find(
      needles: ["func t("],
      in: ["gone.swift"],
    ) == .missing)
  }

  @Test
  func `a line holding two of the needles counts once`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.kt",
      "fun `t`() fun t()\n",
    )
    var searcher = searcher(folder)

    #expect(
      searcher.find(
        needles: ["fun `t`(", "fun t("],
        in: ["a.kt"],
      )
        == .found(
          file: "a.kt",
          line: 1,
        ),
    )
  }

  @Test
  func `a file that is not UTF-8 text is left out of the search`() throws {
    let folder = try TemporaryFolder()

    try folder.writeBytes(
      "bad.swift",
      [0xFF, 0xFE, 0x66, 0x75, 0x6E, 0x63, 0x20, 0x74, 0x28],
    )
    try folder.write(
      "good.swift",
      "func t() {}\n",
    )
    var searcher = searcher(folder)

    #expect(
      searcher.find(
        needles: ["func t("],
        in: ["bad.swift", "good.swift"],
      )
        == .found(
          file: "good.swift",
          line: 1,
        ),
    )
  }

  @Test
  func `lines are counted by line feed, whatever carriage returns precede them`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.swift",
      "one\r\ntwo\r\nfunc t() {}\r\n",
    )
    var searcher = searcher(folder)

    #expect(
      searcher.find(
        needles: ["func t("],
        in: ["a.swift"],
      ) == .found(file: "a.swift", line: 3),
    )
  }

  @Test
  func `each file is read once however often it is searched`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.swift",
      "func t() {\n}\n",
    )
    var searcher = searcher(folder)

    let first = searcher.find(
      needles: ["func t("],
      in: ["a.swift"],
    )
    try folder.write(
      "a.swift",
      "nothing here\n",
    )
    let second = searcher.find(
      needles: ["func t("],
      in: ["a.swift"],
    )

    #expect(first == .found(
      file: "a.swift",
      line: 1,
    ))
    #expect(second == first)
  }

  @Test
  func `files come through the reader it is given, not the disk`() {
    var searcher = SourceSearcher(
      paths: WorkspacePaths(codeRoot: "/w"),
      reader: MockReportReader(texts: ["/w/a.swift": "\n\nfunc t() {\n}\n"]),
    )

    #expect(
      searcher.find(
        needles: ["func t("],
        in: ["a.swift"],
      ) == .found(file: "a.swift", line: 3),
    )
  }
}
