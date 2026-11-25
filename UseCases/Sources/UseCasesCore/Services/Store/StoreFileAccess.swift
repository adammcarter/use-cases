import Foundation

/// Opens the files of the store without ever following a symlink, and reads them as JSON.
struct StoreFileAccess: StoreFileAccessing {
  private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

  private let fileSystem: any FileSystemReading
  private let json: any JSONReading

  init(
    fileSystem: any FileSystemReading,
    json: any JSONReading,
  ) {
    self.fileSystem = fileSystem
    self.json = json
  }

  /// What is at this place, without looking through a symlink; `nil` when nothing is.
  func kind(of file: StoreFile) throws(StoreProblem) -> FileEntryKind? {
    do {
      return try fileSystem.kindOfItem(at: file.url)
    } catch {
      throw StoreProblem(
        location: file.location,
        reason: .unreadable(error.description),
      )
    }
  }

  /// The names in a folder.
  func entries(in folder: StoreFile) throws(StoreProblem) -> [FileEntry] {
    do {
      return try fileSystem.entries(in: folder.url)
    } catch {
      throw StoreProblem(
        location: folder.location,
        reason: .unreadable(error.description),
      )
    }
  }

  /// The exact bytes of a file that has to be there. A sealed run missing it, or holding anything
  /// but a regular file in its place, is corrupt.
  func requiredBytes(of file: StoreFile) throws(StoreProblem) -> [UInt8] {
    switch try kind(of: file) {
    case nil:
      throw .corrupt(file.location, "the file is missing")
    case .file?:
      return try read(file)
    case .directory?:
      throw .corrupt(file.location, "it is a folder, not a file")
    case .symlink?:
      throw .corrupt(file.location, "it is a symlink, not a file")
    case .other?:
      throw .corrupt(file.location, "it is not a regular file")
    }
  }

  /// The bytes of a file below a folder, found by walking its path one name at a time so that no
  /// symlink on the way is followed. `nil` when a name on the way is not there.
  func bytes(
    below folder: StoreFile,
    path: String,
  ) throws(StoreProblem) -> [UInt8]? {
    guard let file = try found(below: folder, path: path) else {
      return nil
    }

    return try read(file)
  }

  /// The SHA-256 and the length of a file found as ``bytes(below:path:)`` finds it, read a chunk
  /// at a time.
  func streamedFile(
    below folder: StoreFile,
    path: String,
    using hasher: any Hashing,
  ) throws(StoreProblem) -> StreamedFile? {
    guard let file = try found(below: folder, path: path) else {
      return nil
    }

    do {
      return try fileSystem.chunks(of: file.url).streamedFile(using: hasher)
    } catch {
      throw StoreProblem(
        location: file.location,
        reason: .unreadable(error.description),
      )
    }
  }

  /// The regular file at a path below a folder, found by walking its path one name at a time so
  /// that no symlink on the way is followed. `nil` when a name on the way is not there.
  private func found(
    below folder: StoreFile,
    path: String,
  ) throws(StoreProblem) -> StoreFile? {
    var current = folder
    let names = path.splitOnScalar("/")

    for (index, name) in names.enumerated() {
      current = current.appending(name)
      guard let kind = try kind(of: current) else {
        return nil
      }

      if index == names.count - 1 {
        guard kind == .file else {
          throw .corrupt(current.location, "it is not a regular file")
        }
      } else if kind != .directory {
        throw .corrupt(current.location, "it is not a folder")
      }
    }

    return current
  }

  func files(below folder: StoreFile) throws(StoreProblem) -> [String] {
    guard let kind = try kind(of: folder) else {
      return []
    }
    guard kind == .directory else {
      throw .corrupt(folder.location, "it is not a folder")
    }

    var found: [String] = []
    try collectFiles(
      in: folder,
      prefix: "",
      into: &found,
    )

    return found.sorted { left, right in
      left.precedesExactly(right)
    }
  }

  func document(
    _ bytes: [UInt8],
    in file: StoreFile,
  ) throws(StoreProblem) -> AuthoredValue {
    try document(
      bytes,
      location: file.location,
      context: "",
    )
  }

  func document(
    line bytes: [UInt8],
    number: Int,
    in file: StoreFile,
  ) throws(StoreProblem) -> AuthoredValue {
    try document(
      bytes,
      location: file.location,
      context: "line \(number): ",
    )
  }

  private func collectFiles(
    in folder: StoreFile,
    prefix: String,
    into found: inout [String],
  ) throws(StoreProblem) {
    for entry in try entries(in: folder) {
      if entry.kind == .directory {
        try collectFiles(
          in: folder.appending(entry.name),
          prefix: prefix + entry.name + "/",
          into: &found,
        )
      } else {
        found.append(prefix + entry.name)
      }
    }
  }

  private func document(
    _ bytes: [UInt8],
    location: String,
    context: String,
  ) throws(StoreProblem) -> AuthoredValue {
    if bytes.starts(with: Self.byteOrderMark) {
      throw .corrupt(location, "\(context)it starts with a byte order mark")
    }
    guard let text = String(bytes: bytes, encoding: .utf8) else {
      throw .corrupt(location, "\(context)it is not valid UTF-8 text")
    }

    do {
      return try json.read(text)
    } catch {
      throw .corrupt(location, "\(context)it is not JSON: \(error.description)")
    }
  }

  private func read(_ file: StoreFile) throws(StoreProblem) -> [UInt8] {
    do {
      return try fileSystem.readBytes(at: file.url)
    } catch {
      throw StoreProblem(
        location: file.location,
        reason: .unreadable(error.description),
      )
    }
  }
}
