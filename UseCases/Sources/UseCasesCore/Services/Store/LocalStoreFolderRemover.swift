import Foundation

/// Lists, moves and deletes folders on the real file system.
struct LocalStoreFolderRemover: StoreFolderRemoving {
  func folderNames(in folder: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []

    return names.filter { name in
      let attributes = try? FileManager.default.attributesOfItem(
        atPath: folder.appendingPathComponent(name).path,
      )

      return attributes?[.type] as? FileAttributeType == .typeDirectory
    }.sorted()
  }

  func exists(_ item: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: item.path)) != nil
  }

  func move(
    _ folder: URL,
    to destination: URL,
  ) throws(StoreFolderError) {
    do {
      try FileManager.default.moveItem(
        at: folder,
        to: destination,
      )
    } catch {
      throw StoreFolderError(reason: error.localizedDescription)
    }
  }

  func delete(_ item: URL) throws(StoreFolderError) {
    do {
      try FileManager.default.removeItem(at: item)
    } catch {
      throw StoreFolderError(reason: error.localizedDescription)
    }
  }
}
