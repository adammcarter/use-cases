import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct RenderCommandTests {
  private static let proposal = """
  title: Wallet and refunds
  remove: [shop.pay.gift]
  save:
    - id: shop.pay.wallet
      title: Wallet, retitled
      value_tier: critical
      intent: The wallet pays first.
      scenarios:
        - id: first
          given: [A wallet with funds.]
          when: [The person pays.]
          then: [The wallet is charged.]
        - id: empty
          when: [The wallet is empty.]
          then: [The card is charged.]
      validation:
        - id: check
          type: { kind: unit }
          covers: [first, empty]
    - id: shop.refunds.partial
      title: Refund part
      value_tier: core
  untouched: [shop.pay.card]
  you_see:
    shop.pay.wallet: the wallet charged first
  decisions:
    - question: a refund larger than paid
      options: [refused, capped at what was paid]
  golden:
    shop.pay.wallet: [empty]
  """

  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
    try workspace.folder.write("proposal.yml", Self.proposal)
  }

  private func render(
    _ kind: String,
    _ flags: [String] = [],
    file: String = "proposal.yml",
  ) async -> CommandResult {
    await workspace.run(["render", kind, "--file", file] + flags)
  }

  private func renderJSON(_ kind: String) async throws -> JSONValue {
    try await workspace.run(["--json", "render", kind, "--file", "proposal.yml"]).document()
  }

  // MARK: - Intent

  @Test
  func `an intent is drawn without any workspace`() async throws {
    let folder = try TemporaryFolder()
    try folder.write(
      "intent.yml",
      "what: Refund part\nwhy: Items come back\nwho: [staff, customers]\n",
    )

    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: ["render", "intent", "--file", "intent.yml"])

    #expect(result.exitCode == 0)
    #expect(result.outputLines == [
      "WHAT   Refund part",
      "WHY    Items come back",
      "WHO    staff · customers",
    ])
  }

  @Test
  func `an intent needs what and why`() async throws {
    try workspace.folder.write("intent.json", #"{"what": "x"}"#)

    let result = await workspace.run(["render", "intent", "--file", "intent.json"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("intent has `what` and `why`"))
  }

  // MARK: - The layouts of a proposal

  @Test
  func `the brief is a card for each change, the removed one showing what goes`() async {
    let result = await render("brief")
    let found = result.outputLines

    #expect(result.exitCode == 0)
    let tops = found.filter { line in
      line.hasPrefix("┌")
    }

    #expect(tops.count == 3)
    #expect(tops[0].hasSuffix(" shop.refunds.partial ──┐"))
    #expect(tops[1].hasSuffix(" shop.pay.wallet ──┐"))
    #expect(tops[2].hasSuffix(" shop.pay.gift ──┐"))
    #expect(found.allSatisfy { line in
      line.unicodeScalars.count == 63 || line.isEmpty
    })
    #expect(found.contains("│  CHANGES · critical                                         │"))
    #expect(result.standardOutput.contains("◇ edge     given A wallet with funds: The person pays"))
    #expect(result.standardOutput.contains("✓ golden   The wallet is empty → The card is charged"))
    #expect(found.contains("│    Removed.                                                 │"))
    #expect(!result.standardOutput.contains("shop.pay.card"))
  }

  @Test
  func `the proposal is the whole change, in the order new, changes, replaces, untouched`(
  ) async {
    let result = await render("proposal")

    #expect(result.exitCode == 0)
    #expect(result.outputLines.first == "PROPOSAL · Wallet and refunds")
    let fits = result.outputLines.dropFirst(2).prefix(4).map { line in
      line.split(separator: " ").prefix(2).joined(separator: " ")
    }

    #expect(fits == [
      "+ NEW",
      "~ CHANGES",
      "− REPLACES",
      "= UNTOUCHED",
    ])
    #expect(result.standardOutput.contains("you'll see: the wallet charged first"))
    #expect(result.standardOutput
      .contains("YOUR CALL    a refund larger than paid:  1) refused   2) capped at what was paid"))
    #expect(result.standardOutput.contains("SIGN-OFF     yours: 1 critical, 2 core"))
    #expect(result.outputLines.last?.hasSuffix("shop.pay.card") == true)
  }

  @Test
  func `the document's text is the plain layout, never bold`() async throws {
    let plain = await render("proposal")
    let document = try await renderJSON("proposal")

    #expect(document["text"] == .string(plain.outputLines.joined(separator: "\n")))
    #expect(document["kind"] == .string("proposal"))
    #expect(document["command"] == .string("render"))
    #expect(document["model"]?["sign_off"] == .object([
      "critical": .integer(1),
      "core": .integer(2),
    ]))
  }

  @Test
  func `a brief document has a card for each change, was only where there is one`(
  ) async throws {
    let cards = try #require(await renderJSON("brief")["model"]?["cards"])
    guard case let .array(found) = cards else {
      Issue.record("no cards")
      return
    }

    #expect(found.count == 3)
    #expect(found[0]["tier"] == .string("core"))
    #expect(found[0]["was"] == nil)
    #expect(found[1]["fit"] == .string("changes"))
    #expect(found[1]["now"] == .string("The wallet pays first."))
    #expect(found[1]["was"] == .string("wallet."))
    #expect(found[2]["now"] == .string("Removed."))
    #expect(found[2]["was"] == .string("gift."))
  }

  // MARK: - Headers

  // @use-case:cli.people-first-output#swift-tests.no-colour-in-pipes
  @Test
  func `headers are bold only where the colour rule allows, never in a document`() async throws {
    try workspace.folder.write("proposal.yml", Self.proposal)

    let bold = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: workspace.folder.url,
      showsColour: true,
    ).run(arguments: ["render", "proposal", "--file", "proposal.yml"])
    let document = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: workspace.folder.url,
      showsColour: true,
    ).run(arguments: ["--json", "render", "proposal", "--file", "proposal.yml"])
    let text = try document.document()["text"]
    let plain = await render("proposal")

    #expect(bold.standardOutput.contains("\u{1B}[1mPROPOSAL · Wallet and refunds\u{1B}[0m"))
    guard case let .string(documentText)? = text else {
      Issue.record("no text")
      return
    }

    #expect(!documentText.unicodeScalars.contains("\u{1B}"))
    #expect(documentText.hasPrefix("PROPOSAL · Wallet and refunds"))
    #expect(!plain.standardOutput.contains("\u{1B}"))
  }

  // @use-case:end cli.people-first-output#swift-tests.no-colour-in-pipes

  // MARK: - Results, after the proposal is applied

  @Test
  func `results are drawn only after the proposal is applied`() async {
    let before = await render("results")

    #expect(before.exitCode == 2)
    #expect(before.standardError.contains("apply the proposal before its results"))

    let applied = await workspace.run(["apply", "--file", "proposal.yml"])
    #expect(applied.exitCode == 0)

    let after = await render("results")

    #expect(after.exitCode == 0)
    #expect(after.outputLines.first == "RESULTS · Wallet and refunds")
    #expect(after.standardOutput.contains("check ○"))
    #expect(after.standardOutput.contains("− shop.pay.gift"))
    #expect(after.outputLines.contains("  gate   passes"))
  }

  @Test
  func `a gate that blocks is still an answer, exit 0`() async throws {
    _ = await workspace.run(["apply", "--file", "proposal.yml"])
    await workspace.record("shop.pay.card", "fail")

    let result = await render("results")
    let document = try await renderJSON("results")

    #expect(result.exitCode == 0)
    #expect(result.outputLines.contains("  gate   blocked"))
    #expect(document["model"]?["gate"] == .boolean(false))
  }

  @Test
  func `the routes behind a use case are labelled by their ids`() async throws {
    _ = await workspace.run(["apply", "--file", "proposal.yml"])

    let document = try await renderJSON("results")
    let first = try #require(document["model"]?["use_cases"])

    guard case let .array(found) = first else {
      Issue.record("no use cases")
      return
    }

    #expect(found.map { $0["use_case"] } == [
      .string("shop.pay.wallet"),
      .string("shop.refunds.partial"),
    ])
    #expect(found[0]["checks"] == .array([.object([
      "label": .string("check"),
      "status": .string("unverified"),
    ])]))
    #expect(found[1]["status"] == .string("draft"))
    #expect(document["model"]?["removed"] == .array([.string("shop.pay.gift")]))
  }

  // MARK: - The file is the one apply takes

  @Test
  func `the file that is drawn is applied as it is`() async {
    let dry = await workspace.run(["apply", "--file", "proposal.yml", "--dry-run"])

    #expect(dry.exitCode == 0)
    #expect(await render("proposal").exitCode == 0)
  }

  // MARK: - Refusals

  @Test(arguments: [
    ("title: ''\nremove: [shop.pay.gift]\n", "has a `title`"),
    ("title: T\nremove: [shop.pay.gift]\ncolour: blue\n", "unknown: colour"),
    ("title: T\nremove: [shop.pay.gift]\nfits: { shop.pay.gift: new }\n", "extends or changes"),
    (
      "title: T\nremove: [shop.pay.gift]\ndecisions: [{ question: q, options: [only] }]\n",
      "at least two `options`",
    ),
    ("title: T\nremove: [shop.pay.gift]\nuntouched: [shop.pay.nope]\n", "no use case"),
    ("title: T\nremove: [shop.pay.nope]\n", "no use case"),
    (
      "title: T\nremove: [shop.pay.gift]\nyou_see: { shop.pay.card: x }\n",
      "nor leaves untouched",
    ),
    ("title: T\nremove: [shop.pay.gift]\ngolden: { shop.pay.gift: [s] }\n", "does not save"),
    ("title: T\nremove: [shop.pay.gift, shop.pay.gift]\n", "at most once"),
    ("title: T\n", "changes nothing"),
  ])
  func `a bad proposal is refused in words that name what is wrong`(
    text: String,
    message: String,
  ) async throws {
    try workspace.folder.write("bad.yml", text)

    let result = await render("proposal", file: "bad.yml")
    let json = await workspace.run(["--json", "render", "brief", "--file", "bad.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains(message))
    #expect(json.exitCode == 2)
    #expect(try json.document()["command"] == .string("render"))
  }

  @Test
  func `a golden path naming a scenario the use case does not have is refused`() async throws {
    try workspace.folder.write(
      "bad.yml",
      Self.proposal.replacingOccurrences(of: "[empty]", with: "[nope]"),
    )

    let result = await render("brief", file: "bad.yml")

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("scenario 'nope'"))
  }

  @Test
  func `a file that is not there is a usage refusal, and so is a layout that does not exist`(
  ) async {
    let missing = await render("brief", file: "missing.yml")
    let unknown = await render("poster")

    #expect(missing.exitCode == 2)
    #expect(missing.standardError.contains("'missing.yml' is not a file"))
    #expect(unknown.exitCode == 2)
  }

  @Test
  func `the proposal layouts need a workspace, and say so when there is none`() async throws {
    let folder = try TemporaryFolder()
    try folder.write("proposal.yml", Self.proposal)

    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: folder.url,
    ).run(arguments: ["render", "brief", "--file", "proposal.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("no use-cases.yml"))
  }

  @Test
  func `nothing is written`() async throws {
    let before = try String(
      contentsOf: workspace.folder.url.appendingPathComponent("use-cases/pay.yml"),
      encoding: .utf8,
    )

    for kind in ["brief", "proposal"] {
      _ = await render(kind)
    }

    let after = try String(
      contentsOf: workspace.folder.url.appendingPathComponent("use-cases/pay.yml"),
      encoding: .utf8,
    )

    #expect(before == after)
    #expect(!FileManager.default
      .fileExists(atPath: workspace.folder.url.appendingPathComponent("use-cases/refunds.yml")
        .path))
  }
}
