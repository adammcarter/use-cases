import Foundation
import UseCasesCore

/// What `use-cases search` prints (chapter 16 §15): a line for each match for a person, one JSON
/// document for scripts.
struct SearchReport {
  private let page: SearchPage

  init(_ page: SearchPage) {
    self.page = page
  }

  /// A line for each match, a blank line, how many there are and where this page is, and the
  /// hint: the next page, else the first match.
  func humanText(hint: Bool) -> String {
    var lines = listing()

    if !lines.isEmpty {
      lines.append("")
    }

    lines.append(countLine)

    if hint, let line = hintLine {
      lines.append(line)
    }

    return lines.joined(separator: "\n")
  }

  /// The document of `cli-search.schema.json`.
  func jsonText() throws(SearchReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(SearchCommand.name),
      "total": .integer(page.total),
      "offset": .integer(page.offset),
      "page_size": .integer(page.pageSize),
      "matches": .array(page.matches.map(Self.entry)),
      "next": page.next.map(StoreJSONValue.string) ?? .null,
    ])

    guard let text = String(
      bytes: StoreJSONWriter().pretty(document),
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }

  private func listing() -> [String] {
    let idWidth = page.matches.map(\.identifier.count).max() ?? 0
    let titleWidth = page.matches.map(\.title.count).max() ?? 0

    return page.matches.map { match in
      [
        match.status.marked.padded(toWidth: 12),
        match.identifier.padded(toWidth: idWidth),
        match.title.padded(toWidth: titleWidth),
        Self.why(of: match),
      ].joined(separator: "  ")
    }
  }

  /// The strongest reason, and a note when the use case also excludes the words.
  private static func why(of match: SearchMatch) -> String {
    guard let first = match.reasons.first else {
      return ""
    }

    let excludes = first.field != .outOfScope && match.reasons.contains { reason in
      reason.field == .outOfScope
    }

    return first.listing + (excludes ? "  (also out of scope)" : "")
  }

  private var countLine: String {
    MatchCountLine.text(
      total: page.total,
      offset: page.offset,
      shown: page.matches.count,
      hasNext: page.next != nil,
    )
  }

  private var hintLine: String? {
    if let next = page.next {
      return "→ use-cases search --next \(next)"
    }

    return page.matches.first.map { match in
      "→ use-cases show \(match.identifier)"
    }
  }

  private static func entry(_ match: SearchMatch) -> StoreJSONValue {
    .present([
      "use_case": .string(match.identifier),
      "title": .string(match.title),
      "file": .string(match.file),
      "status": .string(match.status.rawValue),
      "value_tier": match.valueTier.map(StoreJSONValue.string),
      "score": .number(match.score),
      "why": .array(match.reasons.map(reason)),
      "definition": match.definition,
    ])
  }

  private static func reason(_ reason: SearchReason) -> StoreJSONValue {
    .present([
      "field": .string(reason.field.rawValue),
      "where": reason.location.map(StoreJSONValue.string),
      "text": .string(reason.text),
    ])
  }
}
