/// `exit-code`: every validation link in `settings.file` gets the same result from the run
/// command's exit code. It needs an exit code, so it works only with `use-cases verify --run`.
struct ExitCodeTransformer: ResultsTransforming {
  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let file = try request.settings.requiredString("file")

    guard let exitCode = request.output.exitCode else {
      return ResultsResponse(
        diagnostics: ["no exit code: exit-code works only with `use-cases verify --run`"],
      )
    }

    let status: ResultStatus = exitCode == 0 ? .pass : .fail
    let results = request.links.filter { link in
      link.role == .validation && link.file == file
    }.map { link in
      LinkResult(
        link: link.key,
        status: status,
        message: "exit code \(exitCode)",
      )
    }

    return ResultsResponse(results: results)
  }
}
