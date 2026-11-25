import Foundation

extension RunWriter {
  func seal(
    _ run: OpenRun,
    termination: RunTermination,
    readReports: [FileDigest],
  ) throws(StoreWritingError) -> RunCompletion {
    let folder = folder(
      of: run.identifier,
      in: run.workspace,
    )

    // Nothing is written until the marker is: an existing one is checked for first.
    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )

    let manifestFile = folder.appending(StoreLayout.manifestFile)
    let manifestBytes = try reading { () throws(StoreProblem) in
      try access.requiredBytes(of: manifestFile)
    }
    let manifest = try checkedManifest(
      manifestBytes,
      in: manifestFile,
      of: run.identifier,
    )

    let resultsFile = folder.appending(StoreLayout.resultsFile)
    let resultsBytes = try reading { () throws(StoreProblem) in
      try access.requiredBytes(of: resultsFile)
    }
    let resultCount = try checkedResultCount(
      resultsBytes,
      in: resultsFile,
      of: folder,
    )

    let completion = try RunCompletion(
      version: 1,
      identifier: run.identifier,
      resultCount: resultCount,
      manifestDigest: hasher.sha256Hex(of: manifestBytes),
      resultsDigest: hasher.sha256Hex(of: resultsBytes),
      details: details(
        of: folder,
        manifest: manifest,
        termination: termination,
        readReports: readReports,
      ),
    )

    try publish(
      completion,
      in: folder,
    )

    return completion
  }

  /// What the marker holds beyond the envelope: when and how the run ended, and the digests of
  /// the files it seals.
  private func details(
    of folder: StoreFile,
    manifest: RunManifest,
    termination: RunTermination,
    readReports: [FileDigest],
  ) throws(StoreWritingError) -> RunCompletion.Details {
    try RunCompletion.Details(
      finishedAt: clock.now().storeTimestamp,
      termination: termination,
      outputDigests: digests(of: folder.appending(StoreLayout.outputsFolder)),
      reportDigests: Self.replacing(
        ReportDigester(access: access, hasher: hasher).digests(
          below: folder.appending(StoreLayout.reportsFolder),
          prefix: "",
        ).digests,
        with: readReports,
      ),
      startDigest: startDigest(
        in: folder,
        of: manifest,
      ),
    )
  }

  func checkedManifest(
    _ bytes: [UInt8],
    in file: StoreFile,
    of identifier: RunIdentifier,
  ) throws(StoreWritingError) -> RunManifest {
    let value = try validated(
      bytes,
      against: checks.run,
      location: file.location,
    )
    let manifest = try decoded(file.location) { () throws(AuthoredShapeError) in
      try RunManifest(authored: AuthoredObject(value, at: ""))
    }

    guard manifest.identifier == identifier else {
      throw .damaged(.corrupt(file.location, "its run_id \(manifest.identifier) is not the run's"))
    }

    return manifest
  }

  /// Every line has to be a result of the schema, ended by a line feed, and no use case + route
  /// may repeat (chapter 12 §7, §21 step 1).
  private func checkedResultCount(
    _ bytes: [UInt8],
    in file: StoreFile,
    of run: StoreFile,
  ) throws(StoreWritingError) -> Int {
    guard let last = bytes.last else {
      return 0
    }
    guard last == 0x0A else {
      throw .damaged(.corrupt(file.location, "the last line has no line feed"))
    }

    var seen: Set<RouteKey> = []
    let lines = bytes.dropLast().split(
      separator: 0x0A,
      omittingEmptySubsequences: false,
    )

    for (offset, line) in lines.enumerated() {
      let value = try validated(
        Array(line),
        against: checks.result,
        location: "\(file.location) line \(offset + 1)",
      )
      let result = try decoded(file.location) { () throws(AuthoredShapeError) in
        try StoredResult(authored: AuthoredObject(value, at: ""))
      }

      try requireIntactAttachments(
        of: result,
        in: run,
      )

      guard
        seen.insert(RouteKey(
          useCase: result.useCase,
          route: result.route,
        )).inserted
      else {
        throw .damaged(.corrupt(file.location, "line \(offset + 1) repeats a use case and route"))
      }
    }

    return lines.count
  }

  /// The SHA-256 of every file below a folder the core seals, by path, in byte order. A run that
  /// has none has an empty list.
  private func digests(of folder: StoreFile) throws(StoreWritingError) -> [FileDigest] {
    let paths = try reading { () throws(StoreProblem) in
      try access.files(below: folder)
    }

    var found: [FileDigest] = []

    for path in paths {
      let streamed = try reading { () throws(StoreProblem) in
        try access.streamedFile(
          below: folder,
          path: path,
          using: hasher,
        )
      }

      guard let streamed else {
        throw .damaged(.corrupt(folder.location, "\(path) went missing while it was digested"))
      }

      found.append(FileDigest(
        path: path,
        digest: streamed.digest,
      ))
    }

    return found
  }

  /// The digest of `start.json`: present exactly when the run has one, which a verify run always
  /// does.
  private func startDigest(
    in folder: StoreFile,
    of manifest: RunManifest,
  ) throws(StoreWritingError) -> String? {
    let start = folder.appending(StoreLayout.startFile)
    let kind = try reading { () throws(StoreProblem) in
      try access.kind(of: start)
    }

    guard kind != nil else {
      if manifest.kind == .verify {
        throw .damaged(.corrupt(start.location, "a verify run has no start stamp"))
      }

      return nil
    }

    let bytes = try reading { () throws(StoreProblem) in
      try access.requiredBytes(of: start)
    }

    return hasher.sha256Hex(of: bytes)
  }

  /// The digests of the files now, with those of the files a transformer read taking the place
  /// of the digests of the same files, and the files only it read added; sorted by path.
  private static func replacing(
    _ now: [FileDigest],
    with read: [FileDigest],
  ) -> [FileDigest] {
    var digests: [String: String] = [:]

    for file in now {
      digests[file.path] = file.digest
    }

    for report in read {
      digests[report.path] = report.digest
    }

    return digests
      .map { path, digest in
        FileDigest(
          path: path,
          digest: digest,
        )
      }
      .sorted { left, right in
        left.path.precedesExactly(right.path)
      }
  }

  private func publish(
    _ completion: RunCompletion,
    in folder: StoreFile,
  ) throws(StoreWritingError) {
    let marker = folder.appending(StoreLayout.completionFile)

    guard let document = completion.document else {
      throw .invalidDocument(
        location: marker.location,
        problems: "a marker of a newer version cannot be written",
      )
    }

    let bytes = printer.pretty(document)
    _ = try validated(
      bytes,
      against: checks.completion,
      location: marker.location,
    )

    try files.publishFile(
      bytes,
      at: marker.url,
    )
  }
}
