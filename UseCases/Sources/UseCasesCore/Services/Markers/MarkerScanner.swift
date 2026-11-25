struct MarkerScanner: MarkerScanning {
  private let sentinelFinder: any SentinelFinding
  private let pairer: any MarkerPairing

  /// Makes the scanner that finds sentinels and pairs them the way chapter 08 says.
  init() {
    self.init(
      sentinelFinder: SentinelFinder(),
      pairer: MarkerPairer(),
    )
  }

  init(
    sentinelFinder: any SentinelFinding,
    pairer: any MarkerPairing,
  ) {
    self.sentinelFinder = sentinelFinder
    self.pairer = pairer
  }

  func scan(
    _ bytes: [UInt8],
    in file: WorkspacePath,
  ) -> MarkerScan {
    if bytes.startsWithWideByteOrderMark {
      return MarkerScan(
        regions: [],
        diagnostics: [.wideByteOrderMark(file)],
      )
    }

    guard sentinelFinder.holdsSentinel(bytes) else {
      return .nothing
    }

    guard bytes.isStrictUTF8 else {
      return MarkerScan(
        regions: [],
        diagnostics: [.notStrictUTF8(file)],
      )
    }

    let lines = LineIndex(bytes)
    let markerFile = MarkerFile(
      bytes: bytes,
      lines: lines,
      sentinels: sentinelFinder.sentinels(
        in: bytes,
        lines: lines,
      ),
    )

    return scan(
      markerFile,
      in: file,
    )
  }

  private func scan(
    _ markerFile: MarkerFile,
    in file: WorkspacePath,
  ) -> MarkerScan {
    var diagnostics: [Diagnostic] = []
    var targets: [String: MarkerTarget] = [:]
    var wellFormed: [MarkerSentinel] = []

    for sentinel in markerFile.sentinels {
      do {
        targets[sentinel.identifier] = try target(
          of: sentinel,
          known: targets,
        )
        wellFormed.append(sentinel)
      } catch {
        diagnostics.append(
          .malformedMarkerIdentifier(
            sentinel,
            in: file,
            because: error,
          ),
        )
      }
    }

    let outcome = pairer.pair(wellFormed)

    guard outcome.problems.isEmpty else {
      diagnostics += outcome.problems.map { problem in
        .markerPairing(
          problem,
          in: file,
        )
      }

      return MarkerScan(
        regions: [],
        diagnostics: diagnostics.inReportOrder,
      )
    }

    let regions = regions(
      of: outcome.pairs,
      in: markerFile,
      targets: targets,
    )

    diagnostics += regions.filter(\.isEmpty).map { region in
      .emptyMarkerRegion(
        region,
        in: file,
      )
    }

    return MarkerScan(
      regions: regions,
      diagnostics: diagnostics.inReportOrder,
    )
  }

  /// What a sentinel names, judging its id. An id run directly followed by an ASCII letter, digit
  /// or underscore is malformed, whatever the run reads as.
  private func target(
    of sentinel: MarkerSentinel,
    known: [String: MarkerTarget],
  ) throws(MarkerTargetError) -> MarkerTarget {
    if !sentinel.followingWord.isEmpty {
      throw sentinel.identifier.isEmpty
        ? .emptyBeforeWord(sentinel.followingWord)
        : .runsIntoWord(sentinel.followingWord)
    }

    if let target = known[sentinel.identifier] {
      return target
    }

    return try MarkerTarget(parsing: sentinel.identifier)
  }

  /// The region of each pair, in the order their start sentinels appear.
  private func regions(
    of pairs: [MarkerPair],
    in markerFile: MarkerFile,
    targets: [String: MarkerTarget],
  ) -> [MarkerRegion] {
    pairs
      .sorted { $0.start.tokenRange.lowerBound < $1.start.tokenRange.lowerBound }
      .compactMap { pair in
        targets[pair.start.identifier].map { target in
          markerFile.region(
            of: pair,
            naming: target,
          )
        }
      }
  }
}
