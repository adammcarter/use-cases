import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

/// `render` holds a proposal file to what `apply` holds it to.
struct RenderProposalRefusalTests {
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

  @Test(arguments: [
    ("elsewhere.x.y", "brief"),
    ("elsewhere.x.y", "proposal"),
    ("shop.y", "brief"),
    ("shop.y", "proposal"),
  ])
  func `a file apply refuses is refused alike by a brief and a proposal`(
    identifier: String,
    kind: String,
  ) async throws {
    try workspace.folder.write(
      "odd.yml",
      "title: T\nsave:\n  - id: \(identifier)\n    title: X\n",
    )

    let applied = await workspace.run(["--json", "apply", "--dry-run", "--file", "odd.yml"])
    let drawn = await workspace.run(["--json", "render", kind, "--file", "odd.yml"])
    let plain = await render(kind, file: "odd.yml")

    #expect(applied.exitCode == 2)
    #expect(drawn.exitCode == 2)
    #expect(plain.exitCode == 2)
    #expect(try drawn.document()["error"]?["message"] == applied.document()["error"]?["message"])
    #expect(try drawn.document()["error"]?["kind"] == applied.document()["error"]?["kind"])
    #expect(plain.standardOutput.isEmpty)
  }

  @Test
  func `fits on a use case that is new is refused`() async throws {
    try workspace.folder.write(
      "fits.yml",
      "title: T\nsave:\n  - id: shop.refunds.partial\n    title: R\n"
        + "fits: { shop.refunds.partial: extends }\n",
    )

    let result = await render("proposal", file: "fits.yml")

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("which is new: its fit follows from the batch"))
  }

  @Test
  func `an intent names no workspace, but one named that is missing is refused like any command`(
  ) async throws {
    try workspace.folder.write("intent.yml", "what: x\nwhy: y\n")

    let intent = await workspace.run(
      ["render", "intent", "--file", "intent.yml", "--workspace", "missing-folder"],
    )
    let validate = await workspace.run(["validate", "--workspace", "missing-folder"])
    let fine = await workspace.run(["render", "intent", "--file", "intent.yml"])

    #expect(intent.exitCode == 2)
    #expect(intent.standardOutput.isEmpty)
    #expect(intent.standardError == validate.standardError)
    #expect(fine.exitCode == 0)
  }
}
