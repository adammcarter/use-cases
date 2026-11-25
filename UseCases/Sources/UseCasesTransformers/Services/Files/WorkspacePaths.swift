import Foundation

/// Paths of one workspace, always spelled the way the contract spells them: relative to the code
/// root, with `/` separators.
struct WorkspacePaths: PathResolving {
  let root: String

  /// The code root with symlinks resolved, so a report spelling the same folder another way still
  /// agrees with it.
  init(codeRoot: String) {
    root = WorkspacePaths.canonical(codeRoot)
  }

  func relativePath(of path: String?) -> String? {
    guard let path else {
      return nil
    }

    let resolved = resolve(
      path,
      in: root,
    )
    let full = WorkspacePaths.canonical(resolved)
    let prefix = root.hasSuffix("/") ? root : root + "/"

    guard full.hasPrefix(prefix), full.count > prefix.count else {
      return nil
    }

    return String(full.dropFirst(prefix.count))
  }

  func resolve(
    _ path: String,
    in directory: String,
  ) -> String {
    if path.hasPrefix("/") {
      return path
    }

    let base = directory.hasPrefix("/") ? directory : root + "/" + directory

    return base + "/" + path
  }

  func absolute(_ path: String) -> String {
    resolve(
      path,
      in: root,
    )
  }

  private static func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path
  }
}
