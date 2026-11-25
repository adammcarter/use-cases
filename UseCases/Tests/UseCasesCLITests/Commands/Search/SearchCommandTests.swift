import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct SearchCommandTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func identifiers(_ arguments: [String]) async throws -> [String] {
    let document = try await workspace.run(["--json", "search"] + arguments).document()

    guard case let .array(matches)? = document["matches"] else {
      return []
    }

    return matches.compactMap { match in
      guard case let .string(identifier)? = match["use_case"] else {
        return nil
      }

      return identifier
    }
  }

  private func message(_ result: CommandResult) throws -> String {
    guard case let .string(text)? = try result.document()["error"]?["message"] else {
      throw LoadFailure()
    }

    return text
  }

  @Test
  func `words find use cases, best first, with why and a hint to show the best`() async {
    let result = await workspace.run(["search", "wallet"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first?.hasPrefix("○ unverified  shop.pay.wallet  Wallet") == true)
    #expect(result.outputLines.first?.contains("id: \"shop.pay.wallet\"") == true)
    #expect(result.outputLines.suffix(2) == ["1 match", "→ use-cases show shop.pay.wallet"])
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `quiet leaves out the hint`() async {
    let result = await workspace.run(["--quiet", "search", "wallet"])

    #expect(result.outputLines.last == "1 match")
  }

  @Test
  func `nothing found is exit 0 with no matches`() async throws {
    let human = await workspace.run(["search", "spaceship"])
    let document = try await workspace.run(["--json", "search", "spaceship"]).document()

    #expect(human.exitCode == 0)
    #expect(human.outputLines == ["no matches"])
    #expect(document["total"] == .integer(0))
    #expect(document["next"] == .null)
  }

  @Test
  func `the flags work before the command or after it`() async {
    let before = await workspace.run(["--json", "search", "wallet"])
    let after = await workspace.run(["search", "wallet", "--json"])

    #expect(before == after)
  }

  @Test
  func `several arguments are one query, and a minus word needs the double hyphen`() async throws {
    #expect(try await identifiers(["card", "wallet", "--exact"]).count == 2)
    #expect(try await identifiers(["--exact", "--", "card -wallet"]) == ["shop.pay.card"])
    #expect(try await identifiers(["--", "-wallet"]).isEmpty)
  }

  @Test
  func `state filters read the states status shows`() async throws {
    try await workspace.recordEveryState()

    #expect(try await identifiers(["use", "--state", "failed"]).isEmpty)
    #expect(try await identifiers(["card", "--state", "failed"]) == ["shop.pay.card"])
    #expect(try await identifiers(["share", "--state", "draft"]) == ["shop.cart.share"])
    #expect(try await identifiers(["add", "--state", "verified"]) == ["shop.cart.add"])
  }

  @Test
  func `pages continue with the token alone`() async throws {
    let first = try await workspace.run(["--json", "search", "shop", "--page-size", "1"])
      .document()
    guard case let .string(token)? = first["next"] else {
      Issue.record("no next token")
      return
    }

    let second = try await workspace.run(["--json", "search", "--next", token]).document()

    #expect(second["offset"] == .integer(1))
    #expect(second["page_size"] == .integer(1))
  }

  @Test(arguments: [
    ["words"], ["--like", "x.yml"], ["--under", "shop"], ["--group", "g"], ["--tier", "core"],
    ["--state", "failed"], ["--in", "title"], ["--exact"], ["--full"], ["--page-size", "5"],
  ])
  func `next continues a search and takes nothing else`(extra: [String]) async throws {
    let result = await workspace.run(["--json", "search", "--next", "ZXhhbXBsZQ"] + extra)

    #expect(result.exitCode == 2)
    #expect(try message(result).contains("--next continues a search"))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
  }

  @Test
  func `search needs words or like, never both`() async throws {
    let none = await workspace.run(["--json", "search"])
    let both = await workspace.run(["--json", "search", "tap", "--like", "x.yml"])

    #expect(none.exitCode == 2)
    #expect(try message(none).contains("needs words"))
    #expect(both.exitCode == 2)
    #expect(try message(both).contains("not both"))
  }

  @Test(arguments: [
    (["--", "-zoom"], "at least one word"),
    (["\"unclosed"], "unclosed"),
    (["x", "--in", "tags"], "--in takes"),
    (["x", "--tier", "urgent"], "--tier takes"),
    (["x", "--state", "green"], "--state takes"),
    (["x", "--page-size", "0"], "--page-size is 1 to 100"),
    (["x", "--page-size", "101"], "--page-size is 1 to 100"),
    (["x", "--page-size", "many"], "--page-size is 1 to 100"),
    (["x", "--under", "shop.nope"], "no use case or id prefix"),
    (["x", "--group", "nope"], "no group"),
    (["--next", "garbage"], "--next takes a token"),
    (["--like", "missing.yml"], "missing.yml"),
  ])
  func `a request that is wrong is a usage error in the words of the design`(
    arguments: [String],
    words: String,
  ) async throws {
    let result = await workspace.run(["--json", "search"] + arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.hasPrefix("error: "))
    #expect(try message(result).contains(words))
    #expect(try result.document()["error"]?["kind"] == .string("usage"))
    #expect(try result.document()["command"] == .string("search"))
  }

  @Test
  func `a page of use cases that changed is refused, not a usage error`() async throws {
    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      search: SearchTools(
        workingDirectory: workspace.folder.url,
        searcher: MockUseCaseSearching(refusing: .changed),
      ),
      workingDirectory: workspace.folder.url,
    ).run(arguments: ["--json", "search", "wallet"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("refused"))
    #expect(try message(result).contains("changed since this search"))
  }

  @Test
  func `like takes a use case from a file and never finds itself`() async throws {
    try workspace.folder.write(
      "draft.yml",
      "id: shop.pay.wallet\ntitle: Wallet payments\nintent: cards and wallets\n",
    )

    let found = try await identifiers(["--like", "draft.yml"])

    #expect(!found.contains("shop.pay.wallet"))
    #expect(found.first == "shop.pay.card")
  }

  @Test
  func `a workspace that is INVALID is refused, not searched`() async throws {
    try workspace.folder.write("use-cases/broken.yml", "use_cases:\n  - id: [oops\n")

    let result = await workspace.run(["--json", "search", "wallet"])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(try result.document()["command"] == .string("search"))
  }

  @Test
  func `search writes nothing`() async {
    _ = await workspace.run(["search", "wallet"])
    _ = await workspace.run(["--json", "search", "shop", "--full"])

    #expect(!FileManager.default.fileExists(
      atPath: workspace.folder.url.appendingPathComponent(".use-cases").path,
    ))
  }
}

private struct LoadFailure: Error {}
