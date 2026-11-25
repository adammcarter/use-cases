import Testing
@testable import UseCasesCore

struct ProcessSupervisorConsoleTests {
  private static let limit = 1024 * 1024
  private static let half = 512 * 1024

  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  /// A shell command that prints `count` of the byte `letter`.
  private static func bytes(
    _ count: Int,
    _ letter: Character,
  ) -> String {
    "head -c \(count) /dev/zero | tr '\\0' \(letter)"
  }

  @Test
  func `a command that prints nothing has an empty console`() async throws {
    let run = try await fixture.run("true")

    #expect(run.console == .empty)
  }

  @Test(arguments: [1, 1000, limit - 1, limit])
  func `up to 1 MiB is kept whole, with no marker`(count: Int) async throws {
    let run = try await fixture.run(Self.bytes(count, "x"))

    #expect(run.console.text == String(repeating: "x", count: count))
    #expect(run.console.omittedByteCount == 0)
  }

  @Test(arguments: [limit + 1, limit + 2, 3_000_000])
  func `more than 1 MiB keeps 1 MiB and a marker that counts what was left out`(
    count: Int,
  ) async throws {
    let run = try await fixture.run(Self.bytes(count, "x"))

    let marker = "\n[... \(count - Self.limit) bytes not kept ...]\n"
    #expect(run.console.omittedByteCount == count - Self.limit)
    #expect(run.console.text.utf8.count == Self.limit + marker.utf8.count)
    #expect(run.console.text.contains(marker))
  }

  @Test
  func `the first and the last 512 KiB are kept and the middle is not`() async throws {
    let script = [
      Self.bytes(Self.half, "a"),
      Self.bytes(1000, "b"),
      Self.bytes(Self.half, "c"),
    ].joined(separator: "; ")

    let run = try await fixture.run(script)

    let expected = String(repeating: "a", count: Self.half)
      + "\n[... 1000 bytes not kept ...]\n"
      + String(repeating: "c", count: Self.half)
    #expect(run.console.text == expected)
    #expect(run.console.omittedByteCount == 1000)
  }

  @Test
  func `a command that reads its input first and then prints a lot keeps both ends`() async throws {
    let script = #"read line || echo "no input"; "# + Self.bytes(3_000_000, "x") + "; echo"

    let run = try await fixture.run(script)

    #expect(run.console.text.hasPrefix("no input\nxxx"))
    #expect(run.console.text.contains("bytes not kept"))
    #expect(run.console.text.hasSuffix("xxx\n"))
    #expect(run.console.text.utf8.count < Self.limit + 100)
  }

  @Test
  func `each kept end is decoded on its own, so a character cut at an edge becomes U+FFFD`()
    async throws
  {
    // "é" is two bytes. The first one ends the first 512 KiB; the second one is the byte just
    // before the last 512 KiB, which therefore start inside it.
    let script = [
      Self.bytes(Self.half - 1, "a"),
      #"printf '\303\251'"#,
      Self.bytes(1000, "b"),
      #"printf '\303\251'"#,
      Self.bytes(Self.half - 1, "c"),
    ].joined(separator: "; ")

    let run = try await fixture.run(script)

    let first = String(repeating: "a", count: Self.half - 1) + "\u{FFFD}"
    let last = "\u{FFFD}" + String(repeating: "c", count: Self.half - 1)
    #expect(run.console.text.hasPrefix(first + "\n[... "))
    #expect(run.console.text.hasSuffix(" bytes not kept ...]\n" + last))
    #expect(!run.console.text.contains("bbb"))
  }

  @Test
  func `bytes that are not UTF-8 become U+FFFD`() async throws {
    let run = try await fixture.run(#"printf 'a\377b\303'"#)

    #expect(run.console.text == "a\u{FFFD}b\u{FFFD}")
  }
}
