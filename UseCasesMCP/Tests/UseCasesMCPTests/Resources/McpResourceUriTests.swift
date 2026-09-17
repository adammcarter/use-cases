import Testing
@testable import UseCasesMCP

/// The URI split, against the same inputs `new URL` was checked with.
struct McpResourceUriTests {
  @Test(arguments: [
    ("uc://matrix", "matrix"),
    ("uc://matrix/status", "matrix/status"),
    ("uc://schemas", "schemas"),
    ("uc://schemas/common.schema.json", "schemas/common.schema.json"),
    ("uc://matrix/", "matrix"),
    ("uc://matrix//status//", "matrix/status"),
    ("uc:matrix", "/matrix"),
    ("uc://", ""),
    ("uc://matrix#fragment", "matrix"),
    ("UC://matrix", "matrix"),
  ])
  func `names the resource the host and path spell`(
    text: String,
    key: String,
  ) throws {
    let uri = try #require(McpResourceUri(text))
    #expect(uri.key == key)
  }

  @Test(arguments: [
    ("uc://matrix?repo=/tmp/x", "/tmp/x"),
    ("uc://matrix/status?repo=/tmp/x", "/tmp/x"),
    ("uc://matrix?repo=../../etc", "../../etc"),
    ("uc://matrix?other=1&repo=/tmp/y", "/tmp/y"),
    ("uc://matrix?repo=/tmp/a&repo=/tmp/b", "/tmp/a"),
    ("uc://matrix?repo=%2Ftmp%2Fz", "/tmp/z"),
    ("uc://matrix?repo=", ""),
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
    let uri = try #require(McpResourceUri("uc://matrix"))
    #expect(uri.repository == nil)
  }

  @Test(arguments: ["https://example.com", "file:///tmp", "matrix", "", "://matrix", "9uc://x"])
  func `anything but a uc URL is no resource at all`(text: String) {
    #expect(McpResourceUri(text) == nil)
  }
}
