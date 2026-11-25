import Foundation
import UseCasesCore

/// What `use-cases prune` prints (chapter 16 §20): a line for each run removed, or that would be,
/// and for each leftover of an interrupted prune; the notes; then the total, which counts what was
/// kept too. "nothing to prune" when there is nothing at all. One JSON document for scripts.
struct PruneReport {
  let removed: [PrunableRun]
  let leftovers: [PruneLeftover]
  let kept: [PrunableRun]
  let leftOver: [PruneLeftover]
  let notes: [String]
  let isDryRun: Bool

  init(
    removed: [PrunableRun],
    leftovers: [PruneLeftover] = [],
    kept: [PrunableRun] = [],
    leftOver: [PruneLeftover] = [],
    notes: [String],
    isDryRun: Bool,
  ) {
    self.removed = removed
    self.leftovers = leftovers
    self.kept = kept
    self.leftOver = leftOver
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// The space freed, or that would be: the runs and leftovers removed, in bytes. A run left over
  /// still takes its space.
  var bytes: Int64 {
    removed.reduce(0) { total, run in
      total + run.bytes
    } + leftovers.reduce(0) { total, leftover in
      total + leftover.bytes
    }
  }

  func humanText() -> String {
    guard !removed.isEmpty || !leftovers.isEmpty || !kept.isEmpty || !leftOver.isEmpty else {
      return (["nothing to prune"] + noteLines).joined(separator: "\n")
    }

    let verb = isDryRun ? "would remove" : "removed"
    let lines = removed.map { run in
      "\(verb)  run \(run.identifier)  \(ByteText.text(run.bytes))"
    } + leftovers.map { leftover in
      "\(verb) leftover  \(leftover.location)  \(ByteText.text(leftover.bytes))"
    }

    return (lines + noteLines + ["", totalLine(verb: verb)]).joined(separator: "\n")
  }

  /// `removed 2 runs · freed 1.2 MB`, with what was kept or left over after it.
  private func totalLine(verb: String) -> String {
    var parts: [String] = []
    var counts: [String] = []

    if !removed.isEmpty {
      counts.append(Self.count(removed.count, "run"))
    }

    if !leftovers.isEmpty {
      counts.append(Self.count(leftovers.count, "leftover"))
    }

    if !counts.isEmpty {
      let freed = isDryRun ? "would free" : "freed"

      parts.append("\(verb) \(counts.joined(separator: ", ")) · \(freed) \(ByteText.text(bytes))")
    }

    if !kept.isEmpty {
      parts.append("kept \(Self.count(kept.count, "run"))")
    }

    if !leftOver.isEmpty {
      parts.append("\(Self.count(leftOver.count, "run")) left over")
    }

    return parts.joined(separator: " · ")
  }

  private static func count(
    _ number: Int,
    _ noun: String,
  ) -> String {
    number == 1 ? "1 \(noun)" : "\(number) \(noun)s"
  }

  func jsonText() throws(PruneReportError) -> String {
    let document = PruneDocument(
      report: self,
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data: Data
    do {
      data = try encoder.encode(document)
    } catch {
      throw .encodingFailed
    }

    guard let text = String(
      bytes: data,
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }

  private var noteLines: [String] {
    notes.map { note in
      "note: \(note)"
    }
  }
}
