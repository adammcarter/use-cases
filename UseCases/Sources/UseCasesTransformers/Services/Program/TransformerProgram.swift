import Foundation

/// The whole program: `use-cases-transformers <name> <job> <request.json> <response.json>`.
/// It finds the named transformer, reads the request, writes the response, and turns every failure
/// into a message and a non-zero exit code.
public struct TransformerProgram: Equatable, Sendable {
  /// A program that runs the bundled transformers.
  public init() {}

  /// Runs with the command-line arguments after the program name.
  public func run(arguments: [String]) -> ProgramOutcome {
    do {
      try perform(arguments: arguments)

      return ProgramOutcome(
        exitCode: 0,
        message: nil,
      )
    } catch {
      return ProgramOutcome(
        exitCode: error.isUsageError ? 2 : 1,
        message: "use-cases-transformers: \(error)",
      )
    }
  }

  private func perform(arguments: [String]) throws(TransformerFailure) {
    guard arguments.count == 4 else {
      throw .missingArguments
    }

    let name = arguments[0]

    guard let transformer = TransformerCatalogue.transformer(named: name) else {
      throw .unknownTransformer(name)
    }

    guard arguments[1] == transformer.job.rawValue else {
      throw .unsupportedJob(
        transformer: name,
        job: arguments[1],
      )
    }

    let request = try readRequest(at: arguments[2])
    let response = try respond(
      to: request,
      using: transformer,
    )

    try write(
      response,
      to: arguments[3],
    )
  }

  private func respond(
    to request: Data,
    using transformer: RegisteredTransformer,
  ) throws(TransformerFailure) -> any Encodable {
    try checkContract(of: request)

    switch transformer {
    case let .results(results):
      let decoded = try decode(
        ResultsRequest.self,
        from: request,
      )

      return try results.results(for: decoded)
    case let .links(links):
      let decoded = try decode(
        LinksRequest.self,
        from: request,
      )

      return try links.links(for: decoded)
    }
  }

  private func readRequest(at path: String) throws(TransformerFailure) -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw .requestUnreadable(
        path: path,
        reason: error.localizedDescription,
      )
    }
  }

  private func checkContract(of request: Data) throws(TransformerFailure) {
    let header = try decode(
      ContractHeader.self,
      from: request,
    )

    guard header.contract == 1 else {
      throw .unsupportedContract(header.contract)
    }
  }

  private func decode<Request: Decodable>(
    _ type: Request.Type,
    from data: Data,
  ) throws(TransformerFailure) -> Request {
    do {
      return try JSONDecoder().decode(
        type,
        from: data,
      )
    } catch {
      throw .requestMalformed(reason: "\(error)")
    }
  }

  private func write(
    _ response: any Encodable,
    to path: String,
  ) throws(TransformerFailure) {
    let encoder = JSONEncoder()

    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]

    do {
      try encoder.encode(response).write(to: URL(fileURLWithPath: path))
    } catch {
      throw .responseUnwritable(
        path: path,
        reason: error.localizedDescription,
      )
    }
  }
}

private struct ContractHeader: Decodable {
  let contract: Int?
}
