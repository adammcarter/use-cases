import Foundation

/// Splits a guide page into its title, its lead paragraph and its `##` sections. A line inside a
/// fenced code block is never a heading.
struct GuideParser: GuideParsing {
  func guide(
    named name: String,
    text: String,
  ) throws(GuideParsingError) -> Guide {
    var lines = text.replacingOccurrences(
      of: "\r\n",
      with: "\n",
    ).split(
      separator: "\n",
      omittingEmptySubsequences: false,
    ).map(String.init)

    guard
      !lines.isEmpty,
      let title = Self.heading(of: lines.removeFirst(), marker: "# ")
    else {
      throw .noTitle
    }

    let parts = Self.parts(of: lines)

    guard let lead = parts.first?.body, !lead.isEmpty else {
      throw .noLead
    }

    return Guide(
      name: name,
      title: title,
      covers: Self.firstParagraph(of: lead),
      text: text,
      sections: [GuideSection(heading: title, body: lead)] + parts.dropFirst().map { part in
        GuideSection(heading: part.heading, body: part.body)
      },
    )
  }

  /// The lines under the title, cut at each `##`: the lead first, with no heading.
  private static func parts(of lines: [String]) -> [Part] {
    var parts = [Part(heading: "", lines: [])]
    var isFenced = false

    for line in lines {
      if line.hasPrefix("```") {
        isFenced.toggle()
      }

      if !isFenced, let heading = heading(of: line, marker: "## ") {
        parts.append(Part(heading: heading, lines: []))
      } else {
        parts[parts.count - 1].lines.append(line)
      }
    }

    return parts
  }

  /// The words after the marker, when the line begins with it and has some.
  private static func heading(
    of line: String,
    marker: String,
  ) -> String? {
    guard line.hasPrefix(marker) else {
      return nil
    }

    let title = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)

    return title.isEmpty ? nil : title
  }

  /// The lines up to the first blank one, on one line.
  private static func firstParagraph(of body: String) -> String {
    body.split(
      separator: "\n",
      omittingEmptySubsequences: false,
    )
    .prefix { line in
      !line.allSatisfy(\.isWhitespace)
    }
    .map { line in
      line.trimmingCharacters(in: .whitespaces)
    }
    .joined(separator: " ")
  }

  private struct Part {
    let heading: String
    var lines: [String]

    var body: String {
      lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
}
