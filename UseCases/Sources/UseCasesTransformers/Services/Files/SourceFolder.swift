import Foundation

/// The files of a workspace on the disk.
struct SourceFolder: SourceListing {
  /// Folders no search goes into at any depth: version control, the store, and dependencies.
  static let skippedAnywhere: Set<String> = [
    ".git",
    ".use-cases",
    ".build",
    ".gradle",
    "node_modules",
  ]

  /// Build output folders, skipped only directly under the folder being searched: a Java package
  /// `com/acme/build/` or a folder `test/build/` is source.
  static let skippedAtTheTop: Set<String> = [
    "build",
    "target",
  ]

  let root: String

  func files(
    matching pattern: String,
    under folder: String,
  ) -> [String] {
    let glob = GlobPattern(pattern)
    var found: [String] = []

    collect(
      folder: folder,
      top: folder,
      into: &found,
    )

    let prefix = folder.isEmpty ? "" : folder + "/"

    return found.filter { path in
      glob.matches(String(path.dropFirst(prefix.count)))
    }
  }

  func files(directlyIn folder: String) -> [String] {
    let absolute = folder.isEmpty ? root : root + "/" + folder
    let names = (try? FileManager.default.contentsOfDirectory(atPath: absolute)) ?? []

    let ordered = names.sorted { first, second in
      first.precedesByCodePoint(second)
    }

    return ordered.compactMap { name in
      guard isFile(absolute + "/" + name) else {
        return nil
      }

      return folder.isEmpty ? name : folder + "/" + name
    }
  }

  private func collect(
    folder: String,
    top: String,
    into found: inout [String],
  ) {
    let absolute = folder.isEmpty ? root : root + "/" + folder
    let listed = (try? FileManager.default.contentsOfDirectory(atPath: absolute)) ?? []
    let names = listed.sorted { first, second in
      first.precedesByCodePoint(second)
    }
    var subfolders: [String] = []

    for name in names {
      let path = folder.isEmpty ? name : folder + "/" + name

      if !isFolder(absolute + "/" + name) {
        found.append(path)
      } else if !isSkipped(
        name,
        in: folder,
        top: top,
      ) {
        subfolders.append(path)
      }
    }

    for subfolder in subfolders {
      collect(
        folder: subfolder,
        top: top,
        into: &found,
      )
    }
  }

  private func isSkipped(
    _ name: String,
    in folder: String,
    top: String,
  ) -> Bool {
    SourceFolder.skippedAnywhere.contains(name)
      || (folder == top && SourceFolder.skippedAtTheTop.contains(name))
  }

  private func isFolder(_ path: String) -> Bool {
    let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType

    return type == .typeDirectory
  }

  private func isFile(_ path: String) -> Bool {
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: path,
      isDirectory: &isFolder,
    )

    return exists && !isFolder.boolValue
  }
}
