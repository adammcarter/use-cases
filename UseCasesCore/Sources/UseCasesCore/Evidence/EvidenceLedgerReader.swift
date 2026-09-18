/// Reads every evidence ledger under `<data root>/evidence`
/// (packages/core/src/evidence/jsonlLedger.ts).
///
/// Directories are walked depth first, each listed in `localeCompare` order;
/// symlinks — to files or directories — are skipped without a diagnostic, and
/// only regular `.jsonl` files whose real path stays inside the evidence root
/// are read. The collected paths are then sorted with a BARE sort, so UTF-16
/// code-unit order decides the ledger order in the end. The evidence root
/// itself is followed if it is a symlink.
///
/// A directory that cannot be listed, a file that cannot be read, or a ledger
/// that is not valid UTF-8 is not a diagnostic: the error escapes.
public enum EvidenceLedgerReader {
  static let duplicateKeysMessage = "Duplicate JSON keys are not allowed."

  /// `<data root>/evidence`.
  public static func evidenceRoot(context: ResolvedWorkspaceContext) -> String {
    NodePath.join(context.dataRoot, "evidence")
  }

  /// `path` relative to the data root, `/`-separated.
  public static func relativePath(
    context: ResolvedWorkspaceContext,
    path: String,
  ) -> String {
    NodePath.relative(from: context.dataRoot, to: path)
  }

  public static func read(context: ResolvedWorkspaceContext) throws(EvidenceEventError)
    -> EvidenceLedgerReadResult
  {
    let root = evidenceRoot(context: context)
    guard NodeFile.exists(atPath: root) else {
      return EvidenceLedgerReadResult(ledgers: [], events: [], diagnostics: [])
    }

    let paths: [String]
    do throws(FileAccessError) {
      paths = try JavaScriptString.sorted(ledgerFiles(
        in: root,
        rootRealPath: NodeFile.realPath(root),
      ))
    } catch {
      throw .fileAccess(error)
    }

    var ledgers: [EvidenceLedgerResult] = []
    var events: [EvidenceEvent] = []
    var diagnostics: [Diagnostic] = []
    for path in paths {
      let bytes: [UInt8]
      do throws(FileAccessError) {
        bytes = try NodeFile.readBytes(atPath: path)
      } catch {
        throw .fileAccess(error)
      }
      let ledger = try parseLedger(
        bytes: bytes,
        relativePath: relativePath(context: context, path: path),
      )
      ledgers.append(ledger.result)
      events += ledger.events
      diagnostics += ledger.diagnostics
    }
    return EvidenceLedgerReadResult(ledgers: ledgers, events: events, diagnostics: diagnostics)
  }

  /// `listJsonlFiles`.
  private static func ledgerFiles(
    in directory: String,
    rootRealPath: String,
  ) throws(FileAccessError) -> [String] {
    var results: [String] = []
    let names = try NodeFile.directoryNames(atPath: directory)
      .sorted(by: JavaScriptStringOrder.localeAscending)
    for name in names {
      let fullPath = NodePath.join(directory, name)
      switch try NodeFile.kind(atPath: fullPath) {
      case .symbolicLink, .other:
        continue
      case .directory:
        results += try ledgerFiles(in: fullPath, rootRealPath: rootRealPath)
      case .regularFile:
        guard NodePath.extname(fullPath) == ".jsonl" else {
          continue
        }
        let relativePath = try NodePath.relative(
          from: rootRealPath,
          to: NodeFile.realPath(fullPath),
        )
        if relativePath.isEmpty
          || (!relativePath.utf16.starts(with: [CodeUnits.fullStop, CodeUnits.fullStop])
            && !NodePath.isAbsolute(relativePath))
        {
          results.append(fullPath)
        }
      }
    }
    return results
  }

  struct ParsedLedger {
    let result: EvidenceLedgerResult
    let events: [EvidenceEvent]
    let diagnostics: [Diagnostic]
  }

  //: @use-case:evidence.ledger.damaged_ledger_replay
  /// `readLedgerFile`, from the bytes on.
  static func parseLedger(
    bytes: [UInt8],
    relativePath: String,
  ) throws(EvidenceEventError) -> ParsedLedger {
    guard let source = UseCaseFileValidator.decodeStrictly(bytes) else {
      throw .invalidEncoding
    }
    let normalized = withoutCarriageReturnsBeforeLineFeeds(Array(source.utf16))
    let endsWithNewline = normalized.last == CodeUnits.lineFeed
    var rawLines = normalized.split(separator: CodeUnits.lineFeed, omittingEmptySubsequences: false)
    if endsWithNewline {
      rawLines.removeLast()
    }

    var reading = LedgerReading(relativePath: relativePath)
    for (index, line) in rawLines.enumerated() {
      let isUnterminatedLast = !endsWithNewline && index == rawLines.count - 1
      reading.read(Array(line), lineNumber: index + 1, isUnterminatedLast: isUnterminatedLast)
    }
    return ParsedLedger(
      result: EvidenceLedgerResult(
        path: relativePath,
        isComplete: !reading.hasTornTail && !reading.hasUnknownScopeDamage,
        eventsLoaded: reading.events.count,
        hasTornTail: reading.hasTornTail,
        hasUnknownScopeDamage: reading.hasUnknownScopeDamage,
      ),
      events: reading.events,
      diagnostics: reading.diagnostics,
    )
  }

  //: @use-case:end evidence.ledger.damaged_ledger_replay

  /// `source.replaceAll("\r\n", "\n")`.
  private static func withoutCarriageReturnsBeforeLineFeeds(_ units: [UInt16]) -> [UInt16] {
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    var index = 0
    while index < units.count {
      if units[index] == CodeUnits.carriageReturn, index + 1 < units.count,
         units[index + 1] == CodeUnits.lineFeed
      {
        index += 1
        continue
      }
      result.append(units[index])
      index += 1
    }
    return result
  }

  /// The loop over one ledger's lines.
  private struct LedgerReading {
    let relativePath: String
    var events: [EvidenceEvent] = []
    var diagnostics: [Diagnostic] = []
    var hasTornTail = false
    var hasUnknownScopeDamage = false

    mutating func read(
      _ line: [UInt16],
      lineNumber: Int,
      isUnterminatedLast: Bool,
    ) {
      let text = CodeUnits.string(line)
      guard !JavaScriptString.trim(text).isEmpty else {
        return
      }
      let location = "\(relativePath):\(lineNumber)"
      if isUnterminatedLast {
        hasTornTail = true
        report("evidence_torn_tail", "Evidence ledger has an unterminated final line.", location)
        return
      }
      if DuplicateJSONKeys.isPresent(in: line) {
        hasUnknownScopeDamage = true
        report("evidence_parse_error", EvidenceLedgerReader.duplicateKeysMessage, location)
        return
      }
      let value: JSONValue
      do throws(SchemaError) {
        value = try JSONParser.parse(text)
      } catch {
        hasUnknownScopeDamage = true
        report("evidence_parse_error", error.message, location)
        return
      }
      guard let event = EvidenceEvent(shape: JavaScriptPropertyOrder.reordered(value)) else {
        hasUnknownScopeDamage = true
        report(
          "evidence_foreign_event",
          "Line is valid JSON but is not an evidence event and was skipped.",
          location,
        )
        return
      }
      events.append(event)
    }

    private mutating func report(
      _ code: String,
      _ message: String,
      _ location: String,
    ) {
      diagnostics.append(Diagnostic(code: code, message: message, sourcePath: location))
    }
  }
}
