import Testing
@testable import UseCasesMCP

/// The URI split, against the same inputs `new URL` was checked with.
struct McpResourceUriTests {
  @Test(arguments: [
    ("use-cases://matrix", "matrix"),
    ("use-cases://matrix/status", "matrix/status"),
    ("use-cases://schemas", "schemas"),
    ("use-cases://schemas/common.schema.json", "schemas/common.schema.json"),
    ("use-cases://matrix/", "matrix"),
    ("use-cases://matrix//status//", "matrix/status"),
    ("use-cases:matrix", "/matrix"),
    ("use-cases://", ""),
    ("use-cases://matrix#fragment", "matrix"),
    ("USE-CASES://matrix", "matrix"),
  ])
  func `names the resource the host and path spell`(
    text: String,
    key: String,
  ) throws {
    let uri = try #require(McpResourceUri(text))
    #expect(uri.key == key)
  }

  @Test(arguments: [
    ("use-cases://matrix?repo=/tmp/x", "/tmp/x"),
    ("use-cases://matrix/status?repo=/tmp/x", "/tmp/x"),
    ("use-cases://matrix?repo=../../etc", "../../etc"),
    ("use-cases://matrix?other=1&repo=/tmp/y", "/tmp/y"),
    ("use-cases://matrix?repo=/tmp/a&repo=/tmp/b", "/tmp/a"),
    ("use-cases://matrix?repo=%2Ftmp%2Fz", "/tmp/z"),
    ("use-cases://matrix?repo=", ""),
  ])
  func `reads the repo out of the query`(
    text: String,
    repository: String,
  ) throws {
    let uri = try #require(McpResourceUri(text))
    #expect(uri.repository == repository)
  }

  @Test
  func `a URI with no query names no repo`() throws {
    let uri = try #require(McpResourceUri("use-cases://matrix"))
    #expect(uri.repository == nil)
  }

  @Test(arguments: [
    "https://example.com",
    "file:///tmp",
    "matrix",
    "",
    "://matrix",
    "9use-cases://x",
  ])
  func `anything but a use-cases URL is no resource at all`(text: String) {
    #expect(McpResourceUri(text) == nil)
  }
}
