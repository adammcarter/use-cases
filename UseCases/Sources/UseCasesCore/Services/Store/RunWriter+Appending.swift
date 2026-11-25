extension RunWriter {
  func append(
    _ result: StoredResult,
    to run: OpenRun,
  ) throws(StoreWritingError) {
    let results = folder(
      of: run.identifier,
      in: run.workspace,
    ).appending(StoreLayout.resultsFile)

    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )

    guard let document = result.document else {
      throw .invalidDocument(
        location: results.location,
        problems: "a result of a newer version cannot be written",
      )
    }

    var line = printer.compact(document)
    _ = try validated(
      line,
      against: checks.result,
      location: results.location,
    )
    line.append(0x0A)

    try files.append(
      line,
      to: results.url,
    )
  }
}
