/// One link between a use case or a route and a place in the repository (chapter 08), as every
/// consumer sees it, whatever its source (chapter 09 §20).
public struct ResolvedLink: Equatable, Sendable {
  /// Whether it was found in the code or written in YAML.
  public let source: LinkSource

  /// The binding it belongs to.
  let identity: LinkIdentity

  /// The file, relative to the workspace root and spelled as it is on disk.
  let path: WorkspacePath

  /// The first and last line it covers, counted from 1. A link that covers a whole file runs
  /// from line 1 to the last line holding any bytes; an empty file is 1 to 1.
  let lines: ClosedRange<Int>

  /// The bytes it is located by in the file, end exclusive: the locator span (chapter 11 §89.5).
  let span: Range<Int>

  /// The bytes it holds, in file order. The span less the lines or tokens of nested sentinels.
  let contentRanges: [Range<Int>]

  /// Where it was written, which is its role.
  public var role: LinkRole {
    identity.role
  }

  /// The full id of the use case.
  public var useCase: String {
    identity.useCase.text
  }

  /// The route of a validation link; `nil` for an implementation link.
  public var route: String? {
    identity.route?.text
  }

  /// The binding id.
  public var binding: String {
    identity.binding.text
  }

  /// The file's path, relative to the workspace root, with `/` separators.
  public var file: String {
    path.text
  }

  /// The first line it covers, counted from 1.
  public var startLine: Int {
    lines.lowerBound
  }

  /// The last line it covers.
  public var endLine: Int {
    lines.upperBound
  }

  /// `<use-case-id>#[<route-id>.]<binding-id>@<file>:<start-line>` (chapter 08 "Link keys"): a
  /// handle for one run, not an identity.
  public var key: String {
    "\(identity.keyPrefix)@\(path.text):\(startLine)"
  }

  /// Makes a link.
  init(
    source: LinkSource,
    identity: LinkIdentity,
    path: WorkspacePath,
    lines: ClosedRange<Int>,
    span: Range<Int>,
    contentRanges: [Range<Int>],
  ) {
    self.source = source
    self.identity = identity
    self.path = path
    self.lines = lines
    self.span = span
    self.contentRanges = contentRanges
  }
}
