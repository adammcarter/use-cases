/// A showcase run's event ledger, `<data root>/showcase-runs/<run id>/events.jsonl`
/// (packages/core/src/showcase/jsonlLedger.ts).
public enum ShowcaseLedger {
  /// `showcaseRunsRoot`.
  public static func runsRoot(context: ResolvedWorkspaceContext) -> String {
    NodePath.join(context.dataRoot, "showcase-runs")
  }

  /// `showcaseRunDir`.
  public static func runDirectory(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
  ) -> String {
    NodePath.join(runsRoot(context: context), runIdentifier)
  }

  /// `showcaseLedgerPath`.
  public static func ledgerPath(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
  ) -> String {
    NodePath.join(runDirectory(context: context, runIdentifier: runIdentifier), "events.jsonl")
  }

  /// `readShowcaseEvents`.
  ///
  /// A missing file is incomplete and empty. The text is split on LF only and
  /// blank lines are skipped. Any line that parses is kept, whatever JSON it
  /// holds. A line that does not parse makes the ledger incomplete: if it is
  /// the LAST element of the split — which it is only when the file does not
  /// end in a newline — reading goes on (there is nothing after it); anywhere
  /// else reading stops there, keeping the events before it.
  public static func read(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
  ) throws(ShowcaseError) -> ShowcaseLedgerRead {
    let path = ledgerPath(context: context, runIdentifier: runIdentifier)
    guard NodeFile.exists(atPath: path) else {
      return ShowcaseLedgerRead(isComplete: false, events: [])
    }
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      throw .fileAccess(error)
    }
    let lines = JavaScriptString.split(text, on: CodeUnits.lineFeed)
    var events: [JSONValue] = []
    var isComplete = true
    for (index, line) in lines.enumerated() {
      if JavaScriptString.trim(line).isEmpty {
        continue
      }
      do throws(SchemaError) {
        try events.append(JavaScriptPropertyOrder.reordered(JSONParser.parse(line)))
      } catch {
        if index == lines.count - 1 {
          isComplete = false
          continue
        }
        return ShowcaseLedgerRead(isComplete: false, events: events)
      }
    }
    return ShowcaseLedgerRead(isComplete: isComplete, events: events)
  }

  /// `appendShowcaseEventLine`: `mkdir -p` the run directory, then open for
  /// append, one write of `JSON.stringify(event) + "\n"`, a best-effort sync,
  /// close. No lock is taken.
  static func appendLine(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
    event: JSONValue,
  ) throws(ShowcaseError) {
    let path = ledgerPath(context: context, runIdentifier: runIdentifier)
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(path))
      try LedgerAppend.appendLine(JSONWriter.encode(event) + "\n", toPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }
}

/// What reading a run ledger found.
public struct ShowcaseLedgerRead: Equatable, Sendable {
  /// False for a missing file or any line that did not parse.
  public let isComplete: Bool
  /// Every parsed line before reading stopped, in file order.
  public let events: [JSONValue]

  /// `{ complete, events }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("complete", .bool(isComplete)),
      ("events", .array(events)),
    ]))
  }
}
