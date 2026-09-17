import Foundation

/// Symlink-safe containment checks for paths that cross a trust boundary.
///
/// Both sides are resolved through their existing prefix, so the check sees
/// THROUGH a symlinked parent without requiring the leaf to exist, and is immune
/// to symlinked-tmpdir aliasing (macOS `/var` -> `/private/var`).
public enum PathContainment {
  /// True when `target` stays inside `root` after symlinks are resolved.
  public static func isContained(
    root: String,
    target: String,
  ) -> Bool {
    let realRoot = realpathOfExistingPrefix(lexicallyResolved(root))
    let realTarget = realpathOfExistingPrefix(lexicallyResolved(target))
    return isSameOrBeneath(root: realRoot, target: realTarget)
  }

  /// Bound a supplied path to `root`, returning the resolved absolute path.
  ///
  /// Throws ``PathError/escape(_:)`` when the path escapes `root`. Use at every
  /// boundary where a supplied path becomes a filesystem read or write, BEFORE
  /// the path is opened.
  public static func resolveContained(
    root: String,
    candidate: String,
    message: String = "Path escapes the workspace boundary.",
  ) throws(PathError) -> String {
    let joined = candidate.hasPrefix("/")
      ? candidate
      : (root as NSString).appendingPathComponent(candidate)
    let resolved = lexicallyResolved(joined)

    guard isContained(root: root, target: resolved) else {
      throw .escape(message)
    }

    return resolved
  }

  /// Collapse `.` and `..` textually, the way Node's `path.resolve` does.
  ///
  /// Deliberately lexical: `..` is removed BEFORE the filesystem is consulted,
  /// so a traversal attempt cannot be laundered through a directory that
  /// happens not to exist.
  private static func lexicallyResolved(_ path: String) -> String {
    let isAbsolute = path.hasPrefix("/")
    var components: [String] = []

    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch component {
      case ".":
        continue
      case "..":
        if let last = components.last, last != ".." {
          components.removeLast()
        } else if !isAbsolute {
          components.append("..")
        }
      default:
        components.append(String(component))
      }
    }

    let joined = components.joined(separator: "/")
    return isAbsolute ? "/" + joined : joined
  }

  /// Resolve symlinks on the deepest existing ancestor, then re-attach the
  /// not-yet-existing suffix, so containment can be judged for a path that has
  /// not been created yet.
  private static func realpathOfExistingPrefix(_ path: String) -> String {
    if FileManager.default.fileExists(atPath: path) {
      if let resolved = realpath(path, nil) {
        defer {
          free(resolved)
        }
        return String(cString: resolved)
      }
      return path
    }

    let parent = (path as NSString).deletingLastPathComponent
    guard !parent.isEmpty, parent != path else {
      return path
    }

    let leaf = (path as NSString).lastPathComponent
    return (realpathOfExistingPrefix(parent) as NSString).appendingPathComponent(leaf)
  }

  /// Segment-aware prefix test, so `/a/bc` is never read as inside `/a/b`.
  private static func isSameOrBeneath(
    root: String,
    target: String,
  ) -> Bool {
    if root == target {
      return true
    }

    let boundary = root.hasSuffix("/") ? root : root + "/"
    return target.hasPrefix(boundary)
  }
}
