import Testing
@testable import UseCasesCore

struct MediaTypeTableTests {
  @Test(arguments: [
    ("shot.png", "image/png"),
    ("photo.jpg", "image/jpeg"),
    ("photo.jpeg", "image/jpeg"),
    ("anim.gif", "image/gif"),
    ("pic.webp", "image/webp"),
    ("logo.svg", "image/svg+xml"),
    ("spec.pdf", "application/pdf"),
    ("notes.txt", "text/plain"),
    ("run.log", "text/plain"),
    ("data.json", "application/json"),
    ("report.xml", "application/xml"),
    ("page.html", "text/html"),
    ("README.md", "text/markdown"),
    ("table.csv", "text/csv"),
    ("demo.mp4", "video/mp4"),
    ("demo.mov", "video/quicktime"),
    ("bundle.zip", "application/zip"),
  ])
  func `each ending in the table has its media type`(
    name: String,
    mediaType: String,
  ) {
    #expect(MediaTypeTable.mediaType(forFileNamed: name) == mediaType)
  }

  @Test(arguments: ["SHOT.PNG", "Shot.Png", "photo.JpEg", "RUN.LOG"])
  func `the ending is matched without regard to case`(name: String) {
    #expect(MediaTypeTable.mediaType(forFileNamed: name) != nil)
  }

  @Test(arguments: [
    "",
    "png",
    "shot.png.bak",
    "shot.png ",
    "archive.tar.gz",
    "notes.rtf",
    "Makefile",
    "shot.pn",
    "shot.pngx",
    "shot.png\u{301}",
  ])
  func `a name whose ending is not in the table has no media type`(name: String) {
    #expect(MediaTypeTable.mediaType(forFileNamed: name) == nil)
  }

  @Test
  func `a name that is only an ending still ends with it`() {
    #expect(MediaTypeTable.mediaType(forFileNamed: ".png") == "image/png")
  }

  @Test
  func `only the letters A to Z are folded, so the answer does not depend on the language`() {
    // The Kelvin sign lowercases to a plain k; the table never gets there.
    #expect(MediaTypeTable.mediaType(forFileNamed: "x.LO\u{212A}") == nil)
    #expect(MediaTypeTable.mediaType(forFileNamed: "x.\u{130}\u{131}") == nil)
  }

  @Test
  func `a name with many dots is matched on its last ending`() {
    #expect(MediaTypeTable.mediaType(forFileNamed: "a.b.c.zip") == "application/zip")
    #expect(MediaTypeTable.mediaType(forFileNamed: "screen shot (1).PNG") == "image/png")
  }
}
