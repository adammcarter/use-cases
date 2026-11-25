extension RunWriter {
  func writeConsole(
    _ console: String,
    of validation: IdentifierSegment,
    in run: OpenRun,
  ) throws(StoreWritingError) {
    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )

    let outputs = folder(
      of: run.identifier,
      in: run.workspace,
    ).appending(StoreLayout.outputsFolder)
    let validationFolder = outputs.appending(validation.text)

    try files.ensureFolder(at: outputs.url)
    try files.ensureFolder(at: validationFolder.url)
    try files.createFile(
      Array(console.utf8),
      at: validationFolder.appending(StoreLayout.consoleFile).url,
    )
    try files.flushFolder(at: validationFolder.url)
    try files.flushFolder(at: outputs.url)
  }
}
