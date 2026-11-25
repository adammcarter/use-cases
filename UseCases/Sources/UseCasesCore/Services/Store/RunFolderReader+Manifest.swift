extension RunFolderReader {
  /// Reads `run.json`, after checking it is the bytes the marker sealed. `nil` when the manifest
  /// is of a newer version: only its `run_id` is read.
  func readManifest(
    _ file: StoreFile,
    completion: RunCompletion,
  ) throws(StoreProblem) -> RunManifest? {
    let bytes = try access.requiredBytes(of: file)
    try requireDigest(
      of: bytes,
      equals: completion.manifestDigest,
      for: file,
    )

    let value = try access.document(
      bytes,
      in: file,
    )
    let object = try objectDocument(
      value,
      in: file,
    )

    if isNewer(value, versionKey: "run_version") {
      let identifier = try decode(file) { () throws(AuthoredShapeError) in
        try object.requiredRunIdentifier("run_id")
      }
      try requireSame(
        identifier,
        as: completion.identifier,
        in: file,
      )

      return nil
    }

    try requireValid(
      value,
      against: checks.run,
      in: file,
    )
    let manifest = try decode(file) { () throws(AuthoredShapeError) in
      try RunManifest(authored: object)
    }
    try requireSame(
      manifest.identifier,
      as: completion.identifier,
      in: file,
    )

    return manifest
  }

  /// Refuses bytes whose SHA-256 is not the one the marker sealed.
  func requireDigest(
    of bytes: [UInt8],
    equals sealed: String,
    for file: StoreFile,
  ) throws(StoreProblem) {
    try requireDigest(
      digest(of: bytes),
      equals: sealed,
      for: file,
    )
  }

  /// Refuses a file whose SHA-256, found by reading it, is not the one the marker sealed.
  func requireDigest(
    _ found: String,
    equals sealed: String,
    for file: StoreFile,
  ) throws(StoreProblem) {
    guard found == sealed else {
      throw .corrupt(file.location, "it is not the file completion.json sealed: its digest differs")
    }
  }

  private func requireSame(
    _ identifier: RunIdentifier,
    as expected: RunIdentifier,
    in file: StoreFile,
  ) throws(StoreProblem) {
    guard identifier == expected else {
      throw .corrupt(file.location, "its run_id \(identifier) is not the folder's, \(expected)")
    }
  }
}
