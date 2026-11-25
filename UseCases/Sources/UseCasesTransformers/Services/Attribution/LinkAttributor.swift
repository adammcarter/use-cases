/// Gives each located test to the validation links whose lines contain it, and writes the response
/// every results transformer shares: the worst result per link, and the tests inside no link.
enum LinkAttributor {
  static func response(
    links: [RequestLink],
    located: [LocatedTest],
    diagnostics: [String],
  ) -> ResultsResponse {
    var linksByFile: [String: [RequestLink]] = [:]

    for link in links where link.role == .validation {
      linksByFile[link.file, default: []].append(link)
    }

    var perLink: [String: [LocatedTest]] = [:]
    var unlinked: [UnlinkedTest] = []

    for test in located {
      let inside = containing(
        test,
        in: linksByFile,
      )

      if inside.isEmpty {
        unlinked.append(
          UnlinkedTest(
            test: test.test,
            file: test.file,
            line: test.line.flatMap { line in
              line >= 1 ? line : nil
            },
            status: test.status,
          ),
        )
      }

      for link in inside {
        perLink[link.key, default: []].append(test)
      }
    }

    return ResultsResponse(
      results: results(from: perLink),
      unlinked: sorted(unlinked),
      diagnostics: diagnostics,
    )
  }

  private static func containing(
    _ test: LocatedTest,
    in linksByFile: [String: [RequestLink]],
  ) -> [RequestLink] {
    guard let file = test.file else {
      return []
    }

    return (linksByFile[file] ?? []).filter { link in
      guard let range = link.range else {
        return true
      }

      guard let line = test.line else {
        return false
      }

      return range.contains(line)
    }
  }

  private static func results(from perLink: [String: [LocatedTest]]) -> [LinkResult] {
    perLink.keys.sorted { first, second in
      first.precedesByCodePoint(second)
    }.compactMap { key in
      let tests = perLink[key] ?? []

      guard let status = ResultStatus.worst(of: tests.map(\.status)) else {
        return nil
      }

      let names = Set(tests.map(\.test)).sorted { first, second in
        first.precedesByCodePoint(second)
      }

      return LinkResult(
        link: key,
        status: status,
        tests: names,
      )
    }
  }

  private static func sorted(_ unlinked: [UnlinkedTest]) -> [UnlinkedTest] {
    unlinked.sorted { first, second in
      let firstFile = first.file ?? ""
      let secondFile = second.file ?? ""

      if firstFile != secondFile {
        return firstFile.precedesByCodePoint(secondFile)
      }

      if (first.line ?? 0) != (second.line ?? 0) {
        return (first.line ?? 0) < (second.line ?? 0)
      }

      return first.test.precedesByCodePoint(second.test)
    }
  }
}
