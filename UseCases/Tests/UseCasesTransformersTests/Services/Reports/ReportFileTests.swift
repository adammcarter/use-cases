import Testing
@testable import UseCasesTransformers

struct ReportFileTests {
  private let reader = ReportFile()

  @Test
  func `a file and a folder are told apart`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "report/a.txt",
      "x",
    )

    #expect(reader.exists(at: folder.absolute("report")))
    #expect(reader.isFolder(at: folder.absolute("report")))
    #expect(reader.exists(at: folder.absolute("report/a.txt")))
    #expect(!reader.isFolder(at: folder.absolute("report/a.txt")))
    #expect(!reader.exists(at: folder.absolute("gone")))
    #expect(!reader.isFolder(at: folder.absolute("gone")))
  }

  @Test
  func `text is read as UTF-8`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "a.txt",
      "héllo 日本\n",
    )

    #expect(try reader.text(at: folder.absolute("a.txt")) == "héllo 日本\n")
  }

  @Test
  func `bytes that are not UTF-8 are refused in a strict report`() throws {
    let folder = try TemporaryFolder()

    try folder.writeBytes(
      "a.txt",
      [0x6F, 0x6B, 0xFF, 0x0A],
    )

    #expect(throws: TransformerFailure.reportMalformed(
      path: folder.absolute("a.txt"),
      reason: "not UTF-8 text",
    )) {
      try reader.text(at: folder.absolute("a.txt"))
    }
  }

  @Test
  func `a bad byte in console output changes only itself`() throws {
    let folder = try TemporaryFolder()
    let bytes = Array("café_works ok\n".utf8) + [0xFF] + Array("\nüber ✓\n".utf8)

    try folder.writeBytes(
      "console.txt",
      bytes,
    )

    #expect(
      try reader
        .lossyText(at: folder.absolute("console.txt")) == "café_works ok\n\u{FFFD}\nüber ✓\n",
    )
  }

  @Test
  func `a file that is not there, or is a folder, cannot be read`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "dir/a.txt",
      "x",
    )

    for path in [folder.absolute("gone"), folder.absolute("dir")] {
      #expect(throws: TransformerFailure.self) {
        try reader.text(at: path)
      }
      #expect(throws: TransformerFailure.self) {
        try reader.lossyText(at: path)
      }
    }
  }

  @Test
  func `source text that is missing or not UTF-8 is nil`() throws {
    let folder = try TemporaryFolder()

    try folder.writeBytes(
      "bad.swift",
      [0xFF, 0xFE],
    )
    try folder.write(
      "good.swift",
      "func t()\n",
    )

    #expect(reader.sourceText(at: folder.absolute("good.swift")) == "func t()\n")
    #expect(reader.sourceText(at: folder.absolute("bad.swift")) == nil)
    #expect(reader.sourceText(at: folder.absolute("gone.swift")) == nil)
  }

  @Test
  func `every file under a folder is listed in name order, folders left out`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "r/b.xml",
      "",
    )
    try folder.write(
      "r/a.xml",
      "",
    )
    try folder.write(
      "r/sub/c.xml",
      "",
    )

    #expect(
      reader.files(under: folder.absolute("r")) == [
        folder.absolute("r/a.xml"),
        folder.absolute("r/b.xml"),
        folder.absolute("r/sub/c.xml"),
      ],
    )
    #expect(reader.files(under: folder.absolute("gone")).isEmpty)
  }
}
