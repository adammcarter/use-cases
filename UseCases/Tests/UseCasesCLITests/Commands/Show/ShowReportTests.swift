import Testing
import UseCasesCore
@testable import UseCasesCLI

struct ShowReportTests {
  private func shown(
    isReady: Bool = true,
    missing: [String] = [],
    approval: ApprovalState = .unapproved,
  ) -> ShownUseCase {
    ShownUseCase(
      identifier: "app.dark.toggle",
      file: "use-cases/dark.yml",
      isReady: isReady,
      missing: missing,
      approval: approval,
      definition: .members([
        "id": .string("app.dark.toggle"),
        "title": .string("Dark mode"),
      ]),
      yamlLines: ["id: app.dark.toggle", "title: Dark mode"],
    )
  }

  @Test
  func `the text is a line saying where and what state, then the YAML`() {
    #expect(ShowReport(shown()).humanText() == """
    # use-cases/dark.yml · READY
    id: app.dark.toggle
    title: Dark mode
    """)
  }

  @Test
  func `a draft says DRAFT`() {
    let text = ShowReport(shown(isReady: false, missing: ["intent"])).humanText()

    #expect(text.hasPrefix("# use-cases/dark.yml · DRAFT\n"))
  }

  @Test(arguments: [ApprovalState.approved, .changed, .unapproved])
  func `the document always carries the approval`(approval: ApprovalState) throws {
    let text = try ShowReport(shown(approval: approval)).jsonText()

    #expect(text.contains("\"approval\": \"\(approval.rawValue)\""))
  }

  @Test
  func `the document is the definition under the fields the schema requires`() throws {
    #expect(try ShowReport(shown(isReady: false, missing: ["intent", "a scenario"]))
      .jsonText() == """
      {
        "approval": "unapproved",
        "command": "show",
        "definition": {
          "id": "app.dark.toggle",
          "title": "Dark mode"
        },
        "file": "use-cases/dark.yml",
        "missing": [
          "intent",
          "a scenario"
        ],
        "output_version": 1,
        "state": "DRAFT",
        "use_case": "app.dark.toggle"
      }

      """)
  }
}
