import Foundation

/// Measures a folder on the real file system, walking it once.
struct StoreMeasurer: StoreMeasuring {
  func bytes(below folder: URL) -> Int64 {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]

    guard let walk = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: keys,
      options: [],
      errorHandler: { _, _ in
        true
      },
    ) else {
      return 0
    }

    var total: Int64 = 0

    for case let file as URL in walk {
      guard
        let values = try? file.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true
      else {
        continue
      }

      total += Int64(values.fileSize ?? 0)
    }

    return total
  }
}
