extension RunFolderReader {
  /// Checks what else the marker seals: `start.json`, present exactly when the marker has its
  /// digest (and always for a verify run), and the console captures, which must be exactly the
  /// files `outputs/` holds. A marker of a newer version is not read beyond its envelope, so
  /// nothing more is checked.
  func checkSealedFiles(
    in folder: StoreFile,
    completion: RunCompletion,
    manifest: RunManifest?,
  ) throws(StoreProblem) {
    guard let details = completion.details else {
      return
    }

    try checkStartStamp(
      folder.appending(StoreLayout.startFile),
      sealed: details.startDigest,
      isRequired: manifest?.kind == .verify,
    )
    try checkOutputs(
      folder.appending(StoreLayout.outputsFolder),
      sealed: details.outputDigests,
    )
  }

  private func checkOutputs(
    _ outputs: StoreFile,
    sealed: [FileDigest],
  ) throws(StoreProblem) {
    let found = try access.files(below: outputs)
    guard Set(found) == Set(sealed.map(\.path)) else {
      throw .corrupt(outputs.location, "outputs do not match completion.json")
    }

    for output in sealed {
      let file = outputs.appending(output.path)
      guard
        let streamed = try access.streamedFile(
          below: outputs,
          path: output.path,
          using: hasher,
        )
      else {
        throw .corrupt(outputs.location, "outputs do not match completion.json")
      }

      try requireDigest(
        streamed.digest,
        equals: output.digest,
        for: file,
      )
    }
  }

  private func checkStartStamp(
    _ file: StoreFile,
    sealed: String?,
    isRequired: Bool,
  ) throws(StoreProblem) {
    guard let sealed else {
      if try access.kind(of: file) != nil {
        throw .corrupt(file.location, "completion.json has no start_sha256 for it")
      }
      if isRequired {
        throw .corrupt(file.location, "a verify run has no start stamp")
      }

      return
    }

    try requireDigest(
      of: access.requiredBytes(of: file),
      equals: sealed,
      for: file,
    )
  }
}
