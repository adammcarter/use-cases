import Foundation
import Testing
@testable import UseCasesCore

/// A workspace on disk for the tests of batches and sign-offs: `app.dark.toggle` and
/// `app.dark.other` in one file, `app.solo.only` alone in another, and a child scope `pay`
/// with `app.pay.card`.
struct BatchFixture {
  let workspace: WorkspaceFixture

  init() throws {
    workspace = try WorkspaceFixture()
    try workspace.write(
      "use-cases/dark.yml",
      YAMLSamples.file(prefix: "dark", YAMLSamples.useCase(), YAMLSamples.useCase("other")),
    )
    try workspace.write(
      "use-cases/solo.yml",
      YAMLSamples.file(prefix: "solo", YAMLSamples.useCase("only")),
    )
    try workspace.write(
      "services/pay/use-cases.yml",
      YAMLSamples.child(prefix: "pay"),
    )
    try workspace.write(
      "services/pay/use-cases/card.yml",
      YAMLSamples.file(prefix: "card", YAMLSamples.useCase("charge")),
    )
  }

  func loaded() throws -> LoadedWorkspace {
    try workspace.loaded()
  }

  /// The text of a file of the workspace, or `nil` when it is not there.
  func text(of path: String) -> String? {
    try? String(
      contentsOf: workspace.directory.location(of: path),
      encoding: .utf8,
    )
  }

  /// Writes a plan the way the shared writer does, and loads the workspace it leaves.
  func loadedAfter(_ plan: WritePlan) throws -> LoadedWorkspace {
    try AtomicPlanWriter().apply(
      plan,
      in: workspace.directory.url,
    )

    return try loaded()
  }

  /// The batch the JSON text holds, read as `apply` reads one.
  func batch(_ json: String) throws -> UseCaseBatch {
    try UseCaseBatchReader(
      reader: MockAuthoredInput(AuthoredInput(name: "stdin", value: authored(json))),
      checker: UseCaseInputChecker(),
    ).read("-")
  }

  /// A batch that saves a use case of the workspace as `show` gives it.
  func savingAsShown(_ identifier: String) throws -> String {
    let shown = try asShown(identifier)

    return "{\"save\": [" + shown + "]}"
  }

  /// A use case of the workspace written as `show` gives it, which `save` takes back.
  func asShown(_ identifier: String) throws -> String {
    let useCase = try #require(
      loaded().useCases.first { useCase in
        useCase.identifier.text == identifier
      },
    )

    return try #require(
      String(
        bytes: StoreJSONWriter()
          .pretty(useCase.definition.document(identifier: useCase.identifier)),
        encoding: .utf8,
      ),
    )
  }
}
