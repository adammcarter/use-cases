/// Node's POSIX `path.isAbsolute` and `path.join`, spelled over UTF-16 code
/// units.
///
/// Not ``WorkspacePath``: its normalize drops a trailing separator and answers
/// `""` where node answers `"."`, and it splits on Swift `Character`s, under
/// which a `/` followed by a combining mark is not a separator at all. The
/// verification context hash reads a file at exactly the path node would have
/// built, so the path is built the way node builds it.
public enum NodePath {
  public static func isAbsolute(_ path: String) -> Bool {
    path.utf16.first == CodeUnits.solidus
  }

  /// `path.join(...parts)`: the non-empty parts joined with `/`, then
  /// normalized; `"."` when nothing is left.
  public static func join(_ parts: String...) -> String {
    let joined = parts.filter { part in
      !part.isEmpty
    }
    .joined(separator: "/")
    return joined.isEmpty ? "." : normalize(joined)
  }

  /// `path.normalize`: `.` and `..` resolved lexically, repeated separators
  /// collapsed, a trailing separator kept.
  public static func normalize(_ path: String) -> String {
    let units = Array(path.utf16)
    guard !units.isEmpty else {
      return "."
    }
    let absolute = units.first == CodeUnits.solidus
    let trailingSeparator = units.last == CodeUnits.solidus
    var segments: [[UInt16]] = []
    for segment in units.split(separator: CodeUnits.solidus, omittingEmptySubsequences: true) {
      if segment.elementsEqual(currentDirectory) {
        continue
      }
      if segment.elementsEqual(parentDirectory) {
        if let last = segments.last, !last.elementsEqual(parentDirectory) {
          segments.removeLast()
        } else if !absolute {
          segments.append(parentDirectory)
        }
        continue
      }
      segments.append(Array(segment))
    }
    var body = Array(segments.joined(separator: [CodeUnits.solidus]))
    if body.isEmpty {
      if absolute {
        return "/"
      }
      return trailingSeparator ? "./" : "."
    }
    if trailingSeparator {
      body.append(CodeUnits.solidus)
    }
    return absolute ? "/" + CodeUnits.string(body) : CodeUnits.string(body)
  }

  private static let currentDirectory: [UInt16] = [CodeUnits.fullStop]
  private static let parentDirectory: [UInt16] = [CodeUnits.fullStop, CodeUnits.fullStop]
}
