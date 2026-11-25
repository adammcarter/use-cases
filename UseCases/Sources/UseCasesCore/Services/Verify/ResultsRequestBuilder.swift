import Foundation

/// Builds the request a results transformer reads: the use cases, every link under its key, where
/// the report is, and the transformer's settings.
struct ResultsRequestBuilder: ResultsRequestBuilding {
  func request(
    for validation: BridgeValidation,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
    reportPath: String,
    exitCode: Int32?,
  ) -> StoreJSONValue {
    let code: StoreJSONValue = if let exitCode {
      .integer(Int(exitCode))
    } else {
      .null
    }

    return .members([
      "contract": .integer(1),
      "job": .string(TransformerJob.results.rawValue),
      "use_cases": .array(
        workspace.useCases.map { useCase in
          useCase.definition.document(identifier: useCase.identifier)
        },
      ),
      "links": .array(links.links.map(Self.document)),
      "output": .members([
        "report_path": .string(reportPath),
        "exit_code": code,
        "working_dir": .string(validation.workingDirectory?.text ?? "."),
      ]),
      "code_root": .string(workspace.root.path),
      "settings": validation.settings.map(StoreJSONValue.init) ?? .object([]),
    ])
  }

  /// A link in the shape a transformer receives (chapter 10 §13): lines, never bytes.
  private static func document(of link: ResolvedLink) -> StoreJSONValue {
    .present([
      "key": .string(link.key),
      "source": .string(link.source.rawValue),
      "use_case": .string(link.useCase),
      "route": link.route.map(StoreJSONValue.string),
      "binding": .string(link.binding),
      "role": .string(link.role.rawValue),
      "file": .string(link.file),
      "range": .members([
        "start": .integer(link.startLine),
        "end": .integer(link.endLine),
      ]),
    ])
  }
}
