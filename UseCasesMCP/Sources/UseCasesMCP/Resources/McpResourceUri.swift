import Foundation

/// A `use-cases://` resource URI, split the way `new URL` splits it
/// (packages/mcp/src/resources.ts `parseUcmUri`).
///
/// The host and the path together name the resource, so `use-cases://matrix/status` is
/// the key `matrix/status`. A `?repo=` query segment names the workspace.
/// Anything that is not a `use-cases:` URL is no resource at all.
public struct McpResourceUri: Sendable, Equatable {
  public let key: String
  public let repository: String?

  public init?(_ text: String) {
    guard let scheme = Self.scheme(of: text), scheme == "use-cases" else {
      return nil
    }
    var rest = String(text.dropFirst(scheme.count + 1))

    // The authority, when the URI has one, runs to the first delimiter.
    var host = ""
    if rest.hasPrefix("//") {
      rest = String(rest.dropFirst(2))
      let end = rest.firstIndex { character in
        character == "/" || character == "?" || character == "#"
      } ?? rest.endIndex
      host = String(rest[rest.startIndex ..< end])
      rest = String(rest[end...])
    }

    // The fragment is not part of either half.
    if let hash = rest.firstIndex(of: "#") {
      rest = String(rest[rest.startIndex ..< hash])
    }
    let query: String
    if let mark = rest.firstIndex(of: "?") {
      query = String(rest[rest.index(after: mark)...])
      rest = String(rest[rest.startIndex ..< mark])
    } else {
      query = ""
    }

    // `pathname.replace(/^\/+/, "").replace(/\/+$/, "")`: only the outermost
    // slashes go, so an interior double slash stays as it was read.
    var path = rest
    while path.hasPrefix("/") {
      path = String(path.dropFirst())
    }
    while path.hasSuffix("/") {
      path = String(path.dropLast())
    }

    key = path.isEmpty ? host : "\(host)/\(path)"
    repository = Self.firstQueryValue(named: "repo", in: query)
  }

  /// The scheme, which `new URL` requires: a letter then letters, digits, `+`,
  /// `-` or `.`, up to the first colon.
  private static func scheme(of text: String) -> String? {
    guard let colon = text.firstIndex(of: ":") else {
      return nil
    }
    let candidate = String(text[text.startIndex ..< colon]).lowercased()
    guard let first = candidate.first, first.isLetter else {
      return nil
    }
    let isValid = candidate.dropFirst().allSatisfy { character in
      character.isLetter || character.isNumber || character == "+" || character == "-"
        || character == "."
    }
    return isValid ? candidate : nil
  }

  /// `searchParams.get(name)`: the first occurrence, percent-decoded, with `+`
  /// read as a space.
  private static func firstQueryValue(
    named name: String,
    in query: String,
  ) -> String? {
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard decoded(String(parts[0])) == name else {
        continue
      }
      return parts.count > 1 ? decoded(String(parts[1])) : ""
    }
    return nil
  }

  private static func decoded(_ text: String) -> String {
    let spaced = text.replacingOccurrences(of: "+", with: " ")
    return spaced.removingPercentEncoding ?? spaced
  }
}
