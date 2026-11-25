import Foundation

/// The file system with a plan laid over it, in memory: what a workspace would hold after the
/// plan, read the way every command reads it, with nothing copied and nothing written. A file the
/// plan creates or replaces reads as the plan's bytes, one it deletes is not there, and the
/// folders above a new file are there. Everything else is the real file system.
struct PlannedFileSystem: FileSystemReading {
  private let base: any FileSystemReading
  private let contents: [String: [UInt8]]
  private let deleted: Set<String>
  private let folders: Set<String>

  /// - Parameters:
  ///   - base: The file system below the plan.
  ///   - plan: The changes laid over it.
  ///   - root: The folder the plan's paths are relative to.
  init(
    base: any FileSystemReading,
    plan: WritePlan,
    root: URL,
  ) {
    var contents: [String: [UInt8]] = [:]
    var deleted: Set<String> = []
    var folders: Set<String> = []
    let canonical = base.canonicalLocation(of: root)

    for change in plan.changes {
      let path = canonical.path + "/" + change.path

      switch change.action {
      case .create, .replace:
        contents[path] = change.bytes
        deleted.remove(path)

        for folder in change.workspacePath.ancestors where !folder.isRoot {
          folders.insert(canonical.path + "/" + folder.text)
        }
      case .delete:
        contents[path] = nil
        deleted.insert(path)
      }
    }

    self.base = base
    self.contents = contents
    self.deleted = deleted
    self.folders = folders
  }

  func canonicalLocation(of url: URL) -> URL {
    base.canonicalLocation(of: url)
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    if contents[url.path] != nil {
      return .file
    }

    if deleted.contains(url.path) {
      return nil
    }

    if folders.contains(url.path) {
      return .directory
    }

    return try base.kindOfItem(at: url)
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    var found: [FileEntry]

    do {
      found = try base.entries(in: folder)
    } catch {
      guard folders.contains(folder.path), case .notFound = error else {
        throw error
      }

      found = []
    }

    found.removeAll { entry in
      deleted.contains(folder.path + "/" + entry.name)
    }

    for path in contents.keys.sorted() where Self.parent(of: path) == folder.path {
      add(
        FileEntry(name: Self.name(of: path), kind: .file),
        to: &found,
      )
    }

    for path in folders.sorted() where Self.parent(of: path) == folder.path {
      add(
        FileEntry(name: Self.name(of: path), kind: .directory),
        to: &found,
      )
    }

    return found
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    guard let bytes = contents[file.path] else {
      return try base.readText(at: file)
    }

    guard let text = String(bytes: bytes, encoding: .utf8) else {
      throw .notUTF8(file)
    }

    return text
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    guard let bytes = contents[file.path] else {
      return try base.readBytes(at: file)
    }

    return bytes
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    try base.targetText(ofSymlinkAt: link)
  }

  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool {
    let below = parent.path + "/" + folder.name + "/"

    let isPlanned = contents.keys.contains { path in
      path.hasPrefix(below) && Self.name(of: path) == name
    }

    if isPlanned {
      return true
    }

    return base.holdsFile(
      named: name,
      below: folder,
      in: parent,
    )
  }

  /// A planned entry replaces the one of the same name, or joins the others.
  private func add(
    _ entry: FileEntry,
    to found: inout [FileEntry],
  ) {
    found.removeAll { existing in
      existing.name == entry.name
    }
    found.append(entry)
  }

  private static func parent(of path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else {
      return ""
    }

    return String(path[..<slash])
  }

  private static func name(of path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else {
      return path
    }

    return String(path[path.index(after: slash)...])
  }
}
