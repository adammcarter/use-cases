extension RunFolderReader {
  /// Reads `results.jsonl`: one JSON object per line, each ended by a line feed, with at most one
  /// result for a use case + route. A sealed log is never tail-repaired, so a missing final line
  /// feed is corruption (chapter 12 §23).
  func readResults(
    _ file: StoreFile,
    completion: RunCompletion,
  ) throws(StoreProblem) -> [StoredResult] {
    let bytes = try access.requiredBytes(of: file)
    try requireDigest(
      of: bytes,
      equals: completion.resultsDigest,
      for: file,
    )

    let lines = try lines(
      of: bytes,
      in: file,
    )
    var results: [StoredResult] = []
    var seen: Set<RouteKey> = []

    for (offset, line) in lines.enumerated() {
      let result = try readResult(
        line,
        number: offset + 1,
        in: file,
      )

      let key = RouteKey(
        useCase: result.useCase,
        route: result.route,
      )
      guard seen.insert(key).inserted else {
        throw .corrupt(
          file.location,
          "line \(offset + 1) repeats \(result.useCase) \(result.route)",
        )
      }
      results.append(result)
    }

    guard results.count == completion.resultCount else {
      throw .corrupt(
        file.location,
        "it holds \(results.count) results, but completion.json says \(completion.resultCount)",
      )
    }

    return results
  }

  /// The lines of a log, without their line feeds.
  private func lines(
    of bytes: [UInt8],
    in file: StoreFile,
  ) throws(StoreProblem) -> [[UInt8]] {
    guard let last = bytes.last else {
      return []
    }
    guard last == 0x0A else {
      throw .corrupt(file.location, "the last line has no line feed")
    }

    let lines = bytes.dropLast().split(
      separator: 0x0A,
      omittingEmptySubsequences: false,
    ).map { line in
      Array(line)
    }

    for (offset, line) in lines.enumerated() where line.isEmpty {
      throw .corrupt(file.location, "line \(offset + 1) is blank")
    }

    return lines
  }

  private func readResult(
    _ line: [UInt8],
    number: Int,
    in file: StoreFile,
  ) throws(StoreProblem) -> StoredResult {
    let value = try access.document(
      line: line,
      number: number,
      in: file,
    )
    let object = try objectDocument(
      value,
      in: file,
    )

    if isNewer(value, versionKey: "record_version") {
      return try decode(file) { () throws(AuthoredShapeError) in
        try StoredResult(envelopeOf: object)
      }
    }

    try requireValid(
      value,
      against: checks.result,
      in: file,
      context: "line \(number): ",
    )

    return try decode(file) { () throws(AuthoredShapeError) in
      try StoredResult(authored: object)
    }
  }
}
