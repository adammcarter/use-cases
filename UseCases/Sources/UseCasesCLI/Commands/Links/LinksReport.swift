import Foundation
import UseCasesCore

/// What `use-cases links` prints (chapter 16 §13): a listing for people, one JSON document for
/// scripts.
struct LinksReport {
  private let links: [ResolvedLink]
  private let warnings: [String]

  /// - Parameters:
  ///   - links: The links to show, already in the order of the links document.
  ///   - warnings: Every warning of the workspace, whatever links are shown.
  init(
    links: [ResolvedLink],
    warnings: [String],
  ) {
    self.links = links
    self.warnings = warnings
  }

  /// One line per link, `<use case>  <role>  <file>:<lines>` with the columns lined up, then each
  /// warning on a line.
  func humanText() -> String {
    var lines = links.isEmpty ? ["no links"] : listing()

    lines += warnings.map { warning in
      "warning: \(warning)"
    }

    return lines.joined(separator: "\n")
  }

  func jsonText() throws(LinksReportError) -> String {
    let document = LinksDocument(
      links: links.map(LinkEntry.init),
      diagnostics: warnings,
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

  private func listing() -> [String] {
    let useCaseWidth = links.map(\.useCase.count).max() ?? 0
    let roleWidth = links.map(\.roleListing.count).max() ?? 0

    return links.map { link in
      [
        link.useCase.padded(toWidth: useCaseWidth),
        link.roleListing.padded(toWidth: roleWidth),
        link.placeListing,
      ].joined(separator: "  ")
    }
  }
}
