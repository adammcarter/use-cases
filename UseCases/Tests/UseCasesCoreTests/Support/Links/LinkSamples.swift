/// Authored YAML and code for the link tests.
enum LinkSamples {
  /// The full id of the use case `definitions` writes under the sample root.
  static let useCase = "app.toggle"

  /// The route the sample use case has.
  static let route = "manual"

  /// A manual binding as an item of a `bindings` list: its text, at the left margin.
  static func binding(
    _ identifier: String,
    file: String,
    start: (line: Int, column: Int?)? = nil,
    end: (line: Int, column: Int?)? = nil,
  ) -> String {
    var locator = "file: \(quoted(file))"

    if let start, let end {
      locator += ", start: " + position(start) + ", end: " + position(end)
    }

    return "- id: \(identifier)\n  kind: manual\n  locator: " + braced(locator) + "\n"
  }

  /// A definition file with one use case, `toggle`, whose own bindings and whose route's bindings
  /// are these items.
  static func definitions(
    bindings: [String] = [],
    routeBindings: [String] = [],
    prefix: String? = nil,
  ) -> String {
    var extra = ""

    if !routeBindings.isEmpty {
      extra += "        bindings:\n" + indented(routeBindings, by: 10)
    }

    if !bindings.isEmpty {
      extra += "    bindings:\n" + indented(bindings, by: 6)
    }

    return YAMLSamples.file(prefix: prefix, YAMLSamples.useCase("toggle", extra: extra))
  }

  /// A region of code for `identifier`, with `body` between its sentinel lines.
  static func marked(
    _ identifier: String,
    _ body: String,
  ) -> String {
    "// @use-case:\(identifier)\n\(body)\n// @use-case:end \(identifier)\n"
  }

  /// A JSON string, which YAML reads as a quoted scalar.
  static func quoted(_ text: String) -> String {
    "\"" + text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  private static func position(_ position: (line: Int, column: Int?)) -> String {
    guard let column = position.column else {
      return braced("line: \(position.line)")
    }

    return braced("line: \(position.line), column: \(column)")
  }

  /// A YAML flow mapping around its members.
  private static func braced(_ members: String) -> String {
    "{ " + members + " }"
  }

  private static func indented(
    _ items: [String],
    by spaces: Int,
  ) -> String {
    let margin = String(repeating: " ", count: spaces)

    return items
      .flatMap { item in
        item.split(separator: "\n", omittingEmptySubsequences: true)
      }
      .map { line in
        margin + line + "\n"
      }
      .joined()
  }
}
