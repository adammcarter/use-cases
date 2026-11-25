import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct DocsCommandTests {
  private struct NoMessage: Error {}

  /// A folder that is no workspace: `docs` is about the tool, and works anywhere.
  private let folder: TemporaryFolder

  init() throws {
    folder = try TemporaryFolder()
  }

  private func run(_ arguments: [String]) async -> CommandResult {
    await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: arguments)
  }

  private func guides(_ arguments: [String]) async throws -> [String] {
    let document = try await run(["--json", "docs"] + arguments).document()

    guard case let .array(matches)? = document["matches"] else {
      return []
    }

    return matches.compactMap { match in
      guard case let .string(guide)? = match["guide"] else {
        return nil
      }

      return guide
    }
  }

  /// Each match as `guide/section`.
  private func sections(_ arguments: [String]) async throws -> [String] {
    let document = try await run(["--json", "docs"] + arguments).document()

    guard case let .array(matches)? = document["matches"] else {
      return []
    }

    return matches.compactMap { match in
      guard case let .string(guide)? = match["guide"],
            case let .string(section)? = match["section"]
      else {
        return nil
      }

      return "\(guide)/\(section)"
    }
  }

  private func message(_ result: CommandResult) throws -> String {
    guard case let .string(text)? = try result.document()["error"]?["message"] else {
      throw NoMessage()
    }

    return text
  }

  @Test
  func `docs is built, and needs no workspace`() async {
    let result = await run(["docs"])

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(result.outputLines.first?.hasPrefix("getting-started") == true)
  }

  @Test
  func `no words lists every guide in the order of the design, with a hint to read the first`()
    async
  {
    let result = await run(["docs"])
    let names = result.outputLines.prefix(8).compactMap { line in
      line.split(separator: " ").first.map(String.init)
    }

    #expect(names == [
      "getting-started", "writing-use-cases", "finding", "linking", "verifying", "reading-status",
      "ci-and-hooks", "quirks",
    ])
    #expect(result.outputLines.suffix(2) == ["", "→ use-cases docs getting-started"])
  }

  // @use-case:docs.guides#swift-tests.one-guide
  @Test
  func `a guide's name shows the guide as written`() async throws {
    let result = await run(["docs", "quirks"])
    let published = try String(
      contentsOf: DocsFolder.url().appending(path: "guides/quirks.md"),
      encoding: .utf8,
    )

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == published)
    #expect(!result.standardOutput.contains("→"))
  }

  // @use-case:end docs.guides#swift-tests.one-guide

  @Test(arguments: ["stale", "stlae"])
  func `words find sections, best first, with a hint to read the best guide`(word: String)
    async throws
  {
    let result = await run(["docs", word])
    let document = try await run(["--json", "docs", word]).document()
    guard case let .array(matches)? = document["matches"], let best = matches.first,
          case let .integer(total)? = document["total"]
    else {
      Issue.record("no matches")
      return
    }

    #expect(result.exitCode == 0)
    #expect(best["guide"] == .string("reading-status"))
    #expect(best["section"] == .string("Reading status"))
    #expect(result.outputLines.first?.hasPrefix("reading-status  Reading status ") == true)
    #expect(result.outputLines.first?.contains("Each state") == true)
    #expect(result.outputLines.suffix(2).first == "\(total) matches")
    #expect(result.outputLines.last == "→ use-cases docs reading-status")
  }

  @Test
  func `quiet leaves out the hint`() async {
    let list = await run(["--quiet", "docs"])
    let found = await run(["--quiet", "docs", "stale"])

    #expect(list.outputLines.last?.hasPrefix("→") == false)
    #expect(found.outputLines.last?.hasSuffix("matches") == true || found.outputLines.last?
      .hasSuffix("match") == true)
  }

  @Test
  func `nothing found is exit 0 with no matches`() async throws {
    let human = await run(["docs", "spaceship"])
    let document = try await run(["--json", "docs", "spaceship"]).document()

    #expect(human.exitCode == 0)
    #expect(human.outputLines == ["no matches"])
    #expect(document["total"] == .integer(0))
    #expect(document["next"] == .null)
  }

  @Test
  func `the flags work before the command or after it`() async {
    let before = await run(["--json", "docs", "stale"])
    let after = await run(["docs", "stale", "--json"])

    #expect(before == after)
  }

  @Test
  func `typos, phrases, minus words and exact work as in search`() async throws {
    #expect(try await guides(["stlae"]).first == "reading-status")
    #expect(try await guides(["stlae", "--exact"]).isEmpty)
    #expect(try await guides(["\"need quotes\""]) == ["quirks"])
  }

  @Test
  func `a minus word leaves out the sections that mention it, and only those`() async throws {
    let every = try await sections(["--page-size", "100", "verify"])
    let without = try await sections(["--page-size", "100", "--", "verify -abort"])

    #expect(every.contains("quirks/Short run ids look alike"))
    #expect(without.contains("quirks/Short run ids look alike") == false)
    #expect(without.contains("verifying/Runs nobody will finish") == false)
    #expect(without.contains("quirks/A failing test does not fail the command"))
  }

  @Test
  func `pages continue with the token alone, and add up to every match`() async throws {
    let everything = try await guides(["the", "--page-size", "100"])
    var pages: [String] = []
    var page = try await run(["--json", "docs", "the", "--page-size", "1"]).document()

    while true {
      guard case let .array(matches)? = page["matches"] else {
        Issue.record("not a page")
        return
      }

      pages += matches.compactMap { match in
        guard case let .string(guide)? = match["guide"] else {
          return nil
        }

        return guide
      }

      guard case let .string(token)? = page["next"] else {
        break
      }

      page = try await run(["--json", "docs", "--next", token]).document()
    }

    #expect(pages == everything)
    #expect(pages.count > 1)
  }

  @Test(arguments: [["words"], ["--exact"], ["--page-size", "5"]])
  func `next continues a search and takes nothing else`(extra: [String]) async throws {
    let result = await run(["--json", "docs", "--next", "ZXhhbXBsZQ"] + extra)

    #expect(result.exitCode == 2)
    #expect(try message(result).contains("--next continues a search"))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
  }

  @Test
  func `the refusal of next alone is on stderr for a person`() async {
    let result = await run(["docs", "--next", "x", "--exact"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("--next continues"))
  }

  @Test(arguments: [
    (["--", "-gotchas"], "at least one word"),
    (["\"unclosed"], "unclosed"),
    (["x", "--page-size", "0"], "--page-size is 1 to 100"),
    (["x", "--page-size", "101"], "--page-size is 1 to 100"),
    (["x", "--page-size", "many"], "--page-size is 1 to 100"),
    (["--next", "garbage"], "--next takes a token"),
  ])
  func `a request that is wrong is a usage error in the words of the design`(
    arguments: [String],
    words: String,
  ) async throws {
    let result = await run(["--json", "docs"] + arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.hasPrefix("error: "))
    #expect(try message(result).contains(words))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(try result.document()["command"] == .string("docs"))
  }

  @Test
  func `a token of search is refused as a usage error`() async throws {
    let workspace = try StatusWorkspace()
    let page = try await workspace.run(["--json", "search", "shop", "--page-size", "1"]).document()
    guard case let .string(token)? = page["next"] else {
      Issue.record("no next token")
      return
    }

    let result = await run(["--json", "docs", "--next", token])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
  }

  @Test
  func `docs works in a workspace that is INVALID, and writes nothing`() async throws {
    try folder.write("use-cases.yml", "root: [oops\n")

    let result = await run(["docs", "stale"])

    #expect(result.exitCode == 0)
    #expect(!FileManager.default.fileExists(
      atPath: folder.url.appendingPathComponent(".use-cases").path,
    ))
  }

  @Test(arguments: [
    (DocsError.search(.changed), "refused"),
    (DocsError.guides(.missing("quirks")), "refused"),
    (DocsError.search(.invalidToken), "usage"),
  ])
  func `guides that changed or cannot be read are refused, not a usage error`(
    error: DocsError,
    kind: String,
  ) throws {
    let command = try DocsCommand.parse(["--json"])
    let result = command.result(answerer: MockDocsAnswering(refusing: error))

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string(kind))
    #expect(try message(result) == error.message)
  }
}
