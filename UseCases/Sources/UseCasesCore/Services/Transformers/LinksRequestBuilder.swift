/// Builds the request a links transformer reads: the use cases, the workspace root, what to leave
/// alone, and its settings.
struct LinksRequestBuilder: LinksRequestBuilding {
  func request(
    for workspace: LoadedWorkspace,
    settings: AuthoredValue?,
  ) -> StoreJSONValue {
    .members([
      "contract": .integer(1),
      "job": .string(TransformerJob.links.rawValue),
      "use_cases": .array(
        workspace.useCases.map { useCase in
          useCase.definition.document(identifier: useCase.identifier)
        },
      ),
      "code_root": .string(workspace.root.path),
      "ignore": .strings(
        UseCasesOwnership(workspace).files.map(\.text),
      ),
      "settings": settings.map(StoreJSONValue.init) ?? .object([]),
    ])
  }
}
