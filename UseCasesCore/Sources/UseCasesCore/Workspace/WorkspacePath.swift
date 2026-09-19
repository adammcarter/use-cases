import Foundation

/// The path arithmetic the workspace resolver needs, spelled the way Node's
/// `path` module spells it — because that is what the TypeScript being ported
/// used, and the answers are part of the behaviour.
///
/// ``PathContainment`` already owns the symlink-safe boundary check used where
/// an attacker-controlled path meets the disk. These are the plainer, purely
/// lexical pieces: `resolve`, `dirname`, and a containment test that
/// deliberately does NOT follow symlinks, because the roots check compares two
/// paths that have already been resolved.
public enum WorkspacePath {
  /// True for a POSIX absolute path.
  static func isAbsolute(_ path: String) -> Bool {
    path.hasPrefix("/")
  }

  /// Collapse `.` and `..` textually, keeping the path's absoluteness.
  ///
  /// Lexical on purpose: `..` goes BEFORE the filesystem is consulted, so a
  /// traversal attempt cannot be laundered through a directory that happens not
  /// to exist. A `..` that would climb past the root is dropped, as Node drops
  /// it.
  static func normalize(_ path: String) -> String {
    let absolute = isAbsolute(path)
    var components: [String] = []

    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch component {
      case ".":
        continue
      case "..":
        if let last = components.last, last != ".." {
          components.removeLast()
        } else if !absolute {
          components.append("..")
        }
      default:
        components.append(String(component))
      }
    }

    let joined = components.joined(separator: "/")
    return absolute ? "/" + joined : joined
  }

  /// Node's `path.resolve(base, value)`: make `value` absolute against `base`,
  /// then normalize. An empty `value` therefore resolves to `base` itself.
  public static func absolute(
    _ value: String,
    relativeTo base: String,
  ) -> String {
    isAbsolute(value) ? normalize(value) : normalize(base + "/" + value)
  }

  /// The parent of `path`, stopping at the root.
  static func dirname(_ path: String) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    if parent.isEmpty {
      return isAbsolute(path) ? "/" : "."
    }
    return parent
  }

  /// `path` resolved through symlinks when it exists, and unchanged when it
  /// does not — so a not-yet-created root still resolves to something usable.
  static func realpathIfExists(_ path: String) -> String {
    guard FileManager.default.fileExists(atPath: path),
          let resolved = realpath(path, nil)
    else {
      return path
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }

  /// True when `child` is `root` or sits beneath it, comparing whole segments
  /// so `/a/bc` is never read as inside `/a/b`.
  public static func isContained(
    root: String,
    child: String,
  ) -> Bool {
    if root == child {
      return true
    }
    let boundary = root.hasSuffix("/") ? root : root + "/"
    return child.hasPrefix(boundary)
  }
}
