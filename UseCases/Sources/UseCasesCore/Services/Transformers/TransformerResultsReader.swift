/// Reads the `results`, `unlinked` and `diagnostics` of a results response.
struct TransformerResultsReader: TransformerResultsReading {
  func read(
    _ response: AuthoredObject,
    from name: String,
    links: Set<String>,
  ) throws(TransformerError) -> TransformerResults {
    let results = try readResults(
      in: response,
      from: name,
      links: links,
    )
    let unlinked = try readUnlinked(
      in: response,
      from: name,
    )
    let diagnostics = try shaped(from: name) { () throws(AuthoredShapeError) in
      try response.strings("diagnostics")
    }

    // Only now, with every result checked, is a member that is not there an error.
    for member in ["results", "unlinked", "diagnostics"] where !response.contains(member) {
      throw .malformedResponse(
        name: name,
        reason: "\(member): this is required",
      )
    }

    return TransformerResults(
      results: results,
      unlinked: unlinked,
      diagnostics: diagnostics,
    )
  }

  private func readResults(
    in response: AuthoredObject,
    from name: String,
    links: Set<String>,
  ) throws(TransformerError) -> [TransformerLinkResult] {
    let entries = try shaped(from: name) { () throws(AuthoredShapeError) in
      try response.objects("results")
    }
    var merged: [TransformerLinkResult] = []
    var positions: [String: Int] = [:]

    for entry in entries {
      let result = try readResult(
        entry,
        from: name,
        links: links,
      )

      if let position = positions[result.link] {
        merged[position] = merged[position].merging(result)
      } else {
        positions[result.link] = merged.count
        merged.append(result)
      }
    }

    return merged
  }

  /// A result names a validation link of the request and one of the four statuses; those two
  /// are checked before its other members.
  private func readResult(
    _ entry: AuthoredObject,
    from name: String,
    links: Set<String>,
  ) throws(TransformerError) -> TransformerLinkResult {
    let link = try shaped(from: name) { () throws(AuthoredShapeError) in
      try entry.requiredString("link")
    }
    let status = try shaped(from: name) { () throws(AuthoredShapeError) in
      try entry.requiredString("status")
    }

    guard links.contains(link) else {
      throw .unknownResultLink(
        name: name,
        link: link,
      )
    }

    guard let verdict = Verdict(rawValue: status) else {
      throw .invalidResultStatus(
        name: name,
        link: link,
        status: status,
      )
    }

    return try shaped(from: name) { () throws(AuthoredShapeError) in
      try TransformerLinkResult(
        link: link,
        status: verdict,
        tests: entry.strings("tests"),
        message: entry.optionalString("message"),
      )
    }
  }

  private func readUnlinked(
    in response: AuthoredObject,
    from name: String,
  ) throws(TransformerError) -> [UnlinkedTest] {
    try shaped(from: name) { () throws(AuthoredShapeError) in
      try response.objects("unlinked").map(UnlinkedTest.init(authored:))
    }
  }

  private func shaped<Value>(
    from name: String,
    _ read: () throws(AuthoredShapeError) -> Value,
  ) throws(TransformerError) -> Value {
    do {
      return try read()
    } catch {
      throw .malformedResponse(
        name: name,
        reason: error.description,
      )
    }
  }
}
