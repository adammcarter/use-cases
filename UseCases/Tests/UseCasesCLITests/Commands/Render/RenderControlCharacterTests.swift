import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Nothing a layout shows can act on a terminal.
struct RenderControlCharacterTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func render(
    _ kind: String,
    file: String,
  ) async -> CommandResult {
    await workspace.run(["render", kind, "--file", file])
  }

  @Test
  func `text the layout shows never carries a character a terminal would act on`() async throws {
    try workspace.folder.write(
      "esc.yml",
      """
      title: T
      save:
        - id: shop.refunds.partial
          title: "Refund \\e[8mhidden\\e[0m \\u202Eflipped"
          value_tier: critical
          intent: "Part \\a of it"
          scenarios:
            - id: s
              when: ["Ask \\e]0;pwned\\a"]
              then: [Done]
          out_of_scope: ["Never \\x9b31m"]
      """,
    )

    for kind in ["brief", "proposal"] {
      let plain = await render(kind, file: "esc.yml")
      let document = try await workspace.run(["--json", "render", kind, "--file", "esc.yml"])
        .document()

      guard case let .string(text)? = document["text"] else {
        Issue.record("no text")
        return
      }

      #expect(plain.exitCode == 0)
      #expect(plain.standardOutput.contains("\\x1B[8mhidden"))
      #expect(!plain.standardOutput.unicodeScalars.contains { $0.isTerminalControl })
      #expect(!text.unicodeScalars.contains { $0.isTerminalControl })
    }

    let raw = await workspace.run(["--json", "render", "brief", "--file", "esc.yml"])

    #expect(raw.standardOutput.contains("\\u001b[8mhidden"))
  }

  @Test
  func `text of the proposal that holds a control character is refused as usage`() async throws {
    try workspace.folder.write(
      "esc.yml",
      "title: T\nremove: [shop.pay.gift]\nyou_see:\n  shop.pay.gift: \"a \\e[8m b\"\n",
    )

    let result = await render("proposal", file: "esc.yml")
    let json = await workspace.run(["--json", "render", "proposal", "--file", "esc.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError
      .contains("`you_see for shop.pay.gift` holds the control character '\\x1B'"))
    #expect(!result.standardError.unicodeScalars.contains { $0.isTerminalControl })
    #expect(try json.document()["error"]?["kind"] == .string("usage"))
  }

  @Test
  func `an id with a control character in a message is spelled out`() async throws {
    try workspace.folder.write(
      "esc.yml",
      "title: T\nremove: [shop.pay.gift]\nuntouched: [\"shop.\\e[8m.x\"]\n",
    )

    let result = await render("proposal", file: "esc.yml")

    #expect(result.exitCode == 2)
    #expect(!result.standardError.unicodeScalars.contains { $0.isTerminalControl })
    #expect(result.standardError.contains("\\x1B"))
  }

  @Test
  func `an intent with a control character is refused, and the document never holds one`(
  ) async throws {
    try workspace.folder.write("intent.yml", "what: \"a \\e[8m b\"\nwhy: y\n")

    let result = await workspace.run(["render", "intent", "--file", "intent.yml"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("`what` holds the control character '\\x1B'"))
  }
}
