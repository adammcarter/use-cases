import Foundation

extension RunWriter {
  func reopenRun(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun {
    try requireUnsealed(
      identifier,
      in: workspace,
    )

    let file = folder(
      of: identifier,
      in: workspace,
    ).appending(StoreLayout.manifestFile)
    let bytes = try reading { () throws(StoreProblem) in
      try access.requiredBytes(of: file)
    }
    let manifest = try checkedManifest(
      bytes,
      in: file,
      of: identifier,
    )

    return OpenRun(
      workspace: workspace,
      manifest: manifest,
    )
  }

  func finalize(
    _ manifest: RunManifest,
    of run: OpenRun,
  ) throws(StoreWritingError) {
    let file = folder(
      of: run.identifier,
      in: run.workspace,
    ).appending(StoreLayout.manifestFile)

    guard manifest.identifier == run.identifier else {
      throw .invalidDocument(
        location: file.location,
        problems: "its run_id \(manifest.identifier) is not the run's",
      )
    }

    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )

    let bytes = printer.pretty(manifest.document)

    _ = try validated(
      bytes,
      against: checks.run,
      location: file.location,
    )
    try files.replaceFile(
      bytes,
      at: file.url,
    )
  }

  func clearResults(of run: OpenRun) throws(StoreWritingError) {
    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )
    try files.replaceFile(
      [],
      at: folder(
        of: run.identifier,
        in: run.workspace,
      ).appending(StoreLayout.resultsFile).url,
    )
  }
}
