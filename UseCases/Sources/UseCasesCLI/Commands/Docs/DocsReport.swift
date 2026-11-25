import Foundation
import UseCasesCore

/// What `use-cases docs` prints (chapter 16 §16): for a person, the list, the guide or a line for
/// each match; for scripts, one JSON document that says which of the three it is.
struct DocsReport {
  private let answer: DocsAnswer

  init(_ answer: DocsAnswer) {
    self.answer = answer
  }

  /// The list of guides with what each covers, a guide as written, or a line for each match, a
  /// blank line, how many there are and where this page is; and the hint: the next page, else the
  /// guide to read.
  func humanText(hint: Bool) -> String {
    switch answer {
    case let .list(guides):
      listing(
        of: guides,
        hint: hint,
      )
    case let .guide(guide):
      guide.text
    case let .page(page):
      listing(
        of: page,
        hint: hint,
      )
    }
  }

  /// The document of `cli-docs.schema.json`.
  func jsonText() throws(DocsReportError) -> String {
    guard let text = String(
      bytes: StoreJSONWriter().pretty(document),
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }

  private func listing(
    of guides: [Guide],
    hint: Bool,
  ) -> String {
    let width = guides.map(\.name.count).max() ?? 0
    var lines = guides.map { guide in
      "\(guide.name.padded(toWidth: width))  \(guide.covers)"
    }

    if hint, let first = guides.first {
      lines += ["", "→ use-cases docs \(first.name)"]
    }

    return lines.joined(separator: "\n")
  }

  private func listing(
    of page: GuidePage,
    hint: Bool,
  ) -> String {
    let guideWidth = page.matches.map(\.guide.count).max() ?? 0
    let sectionWidth = page.matches.map(\.section.count).max() ?? 0
    var lines = page.matches.map { match in
      [
        match.guide.padded(toWidth: guideWidth),
        match.section.padded(toWidth: sectionWidth),
        match.text,
      ].joined(separator: "  ")
    }

    if !lines.isEmpty {
      lines.append("")
    }

    lines.append(
      MatchCountLine.text(
        total: page.total,
        offset: page.offset,
        shown: page.matches.count,
        hasNext: page.next != nil,
      ),
    )

    if hint {
      if let next = page.next {
        lines.append("→ use-cases docs --next \(next)")
      } else if let best = page.matches.first {
        lines.append("→ use-cases docs \(best.guide)")
      }
    }

    return lines.joined(separator: "\n")
  }

  private var document: StoreJSONValue {
    switch answer {
    case let .list(guides):
      .members([
        "output_version": .integer(OutputDocument.version),
        "command": .string(DocsCommand.name),
        "view": .string("list"),
        "guides": .array(
          guides.map { guide in
            .members([
              "guide": .string(guide.name),
              "title": .string(guide.title),
              "covers": .string(guide.covers),
            ])
          },
        ),
      ])
    case let .guide(guide):
      .members([
        "output_version": .integer(OutputDocument.version),
        "command": .string(DocsCommand.name),
        "view": .string("guide"),
        "guide": .string(guide.name),
        "title": .string(guide.title),
        "text": .string(guide.text),
      ])
    case let .page(page):
      .members([
        "output_version": .integer(OutputDocument.version),
        "command": .string(DocsCommand.name),
        "view": .string("search"),
        "total": .integer(page.total),
        "offset": .integer(page.offset),
        "page_size": .integer(page.pageSize),
        "matches": .array(
          page.matches.map { match in
            .members([
              "guide": .string(match.guide),
              "section": .string(match.section),
              "text": .string(match.text),
              "score": .number(match.score),
            ])
          },
        ),
        "next": page.next.map(StoreJSONValue.string) ?? .null,
      ])
    }
  }
}
