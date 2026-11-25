import Foundation

/// The file system of this machine.
struct LocalFileSystem: FileSystemReading {
  /// Resolves with `realpath`, which Darwin and Glibc both have. `URL.resolvingSymlinksInPath`
  /// is not used: it treats `/private/var` specially, and differently on Linux.
  func canonicalLocation(of url: URL) -> URL {
    guard let resolved = realpath(url.path, nil) else {
      return url.standardizedFileURL
    }

    defer {
      free(resolved)
    }

    return URL(
      fileURLWithPath: String(cString: resolved),
      isDirectory: false,
    )
  }

  /// A symlink is found with `destinationOfSymbolicLink` and a folder with `fileExists`, both of
  /// which Darwin and Linux Foundation have. Only a thing that is neither is asked its type, and
  /// anything the type does not call a regular file is `.other`, so it is never opened.
  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    let manager = FileManager.default

    if (try? manager.destinationOfSymbolicLink(atPath: url.path)) != nil {
      return .symlink
    }

    var isDirectory: ObjCBool = false

    if manager.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory,
    ) {
      // A file can go between being seen and being looked at: then it has gone.
      return isDirectory.boolValue ? .directory : try regularOrOther(at: url)
    }

    // Nothing was found: say whether that is because it is not there or cannot be looked at.
    do {
      _ = try manager.attributesOfItem(atPath: url.path)
    } catch {
      if Self.isMissing(error) || !Self.isFolder(url.deletingLastPathComponent()) {
        return nil
      }

      throw .unreadable(url, reason: error.localizedDescription)
    }

    return nil
  }

  /// Linux Foundation reports a file standing where a folder should be as a bare error 256, with
  /// no POSIX code beneath it: so whether anything can be there is asked of the parent instead.
  private static func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false

    return FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory,
    ) && isDirectory.boolValue
  }

  /// Lists with `opendir` and `readdir`, which hand over each name's bytes as the file system
  /// stores them. A name that is not valid UTF-8 is then seen as such, never dropped or repaired.
  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    var entries: [FileEntry] = []
    let names: [[UInt8]]

    do {
      names = try Self.nameBytes(atPath: Array(folder.path.utf8))
    } catch {
      if error.code == ENOENT || error.code == ENOTDIR {
        throw .notFound(folder)
      }

      throw .unreadable(folder, reason: error.reason)
    }

    for bytes in names {
      // A name that vanished since the listing is gone, not an error.
      if let entry = try entry(
        named: bytes,
        in: folder,
      ) {
        entries.append(entry)
      }
    }

    return entries
  }

  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool {
    let target = Array(name.utf8)
    var pending = [Array(parent.path.utf8) + [Self.slash] + folder.nameBytes]

    while let path = pending.popLast() {
      guard let names = try? Self.nameBytes(atPath: path) else {
        continue
      }

      for bytes in names {
        let child = path + [Self.slash] + bytes

        switch try? Self.kindOfItem(atPath: child) {
        case .file?, .symlink?:
          if bytes == target {
            return true
          }
        case .directory?:
          pending.append(child)
        default:
          break
        }
      }
    }

    return false
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    guard let data = FileManager.default.contents(atPath: file.path) else {
      throw .unreadable(file, reason: "it could not be opened")
    }

    guard let decoded = String(bytes: data, encoding: .utf8) else {
      throw .notUTF8(file)
    }

    // Foundation drops a leading byte order mark on some systems and keeps it on others. It is
    // always kept here, so the settings reader sees the same text everywhere.
    let hasMark = data.starts(with: Self.byteOrderMark)

    return hasMark && decoded.unicodeScalars.first != "\u{FEFF}" ? "\u{FEFF}" + decoded : decoded
  }

  /// A file that has gone since it was listed is `notFound`, never `unreadable`.
  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    do {
      return try Array(Data(contentsOf: file))
    } catch {
      if Self.isMissing(error) {
        throw .notFound(file)
      }

      throw .unreadable(file, reason: error.localizedDescription)
    }
  }

  func chunks(of file: URL) throws(FileSystemError) -> any FileChunkReading {
    try PosixChunkReader(opening: file)
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    do {
      return try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    } catch {
      if Self.isMissing(error) {
        throw .notFound(link)
      }

      throw .unreadable(link, reason: error.localizedDescription)
    }
  }

  private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

  /// The entry for a name, or `nil` when it has gone.
  private func entry(
    named bytes: [UInt8],
    in folder: URL,
  ) throws(FileSystemError) -> FileEntry? {
    guard bytes.isStrictUTF8 else {
      return try entryForName(notUTF8: bytes, in: folder)
    }

    let name = String(utf8Bytes: bytes)

    return try kindOfItem(at: folder.appendingPathComponent(name)).map { kind in
      FileEntry(name: name, kind: kind)
    }
  }

  private func entryForName(
    notUTF8 bytes: [UInt8],
    in folder: URL,
  ) throws(FileSystemError) -> FileEntry? {
    let kind: FileEntryKind?

    do {
      kind = try Self.kindOfItem(atPath: Array(folder.path.utf8) + [Self.slash] + bytes)
    } catch {
      throw .unreadable(folder, reason: "\(Self.escaped(bytes)): \(error.reason)")
    }

    return kind.map { kind in
      FileEntry(
        name: Self.escaped(bytes),
        kind: kind,
        isNameUTF8: false,
        nameBytes: bytes,
      )
    }
  }

  /// A path's bytes as a NUL-terminated C string. Passed as an array, it reaches `opendir` and
  /// `lstat` as the non-optional pointer Glibc's headers ask for, as well as Darwin's.
  private static func cString(_ path: [UInt8]) -> [CChar] {
    path.map(CChar.init(bitPattern:)) + [0]
  }

  /// The names in a folder, as bytes, without `.` and `..`. Each name is read from the entry
  /// `readdir` returns up to its terminating NUL and no further.
  private static func nameBytes(atPath path: [UInt8]) throws(POSIXFailure) -> [[UInt8]] {
    let handle = opendir(cString(path))

    guard let handle else {
      throw POSIXFailure(code: errno)
    }

    defer {
      closedir(handle)
    }

    var names: [[UInt8]] = []

    while true {
      // `readdir` sets errno only on failure; clearing it first tells the end from a failure.
      errno = 0

      guard let item = readdir(handle) else {
        break
      }

      let name = nameBytes(of: item)

      if name != [0x2E], name != [0x2E, 0x2E] {
        names.append(name)
      }
    }

    guard errno == 0 else {
      throw POSIXFailure(code: errno)
    }

    return names
  }

  /// The bytes of a directory entry's name. The name field is longer than the name, and the
  /// entry `readdir` returns may end inside it, so only the bytes up to the NUL are read.
  private static func nameBytes(of item: UnsafeMutablePointer<dirent>) -> [UInt8] {
    let capacity = MemoryLayout.size(ofValue: item.pointee.d_name)

    return withUnsafePointer(to: &item.pointee.d_name) { field in
      field.withMemoryRebound(to: CChar.self, capacity: capacity) { start in
        let length = strnlen(start, capacity)

        return (0 ..< length).map { index in
          UInt8(bitPattern: start[index])
        }
      }
    }
  }

  /// What is at a path given as bytes, without following a symlink. `nil` when nothing is
  /// there; any other failure is thrown.
  private static func kindOfItem(atPath path: [UInt8]) throws(POSIXFailure) -> FileEntryKind? {
    var information = stat()

    let found = lstat(
      cString(path),
      &information,
    )

    guard found == 0 else {
      let code = errno

      if code == ENOENT || code == ENOTDIR {
        return nil
      }

      throw POSIXFailure(code: code)
    }

    switch information.st_mode & S_IFMT {
    case S_IFDIR:
      return .directory
    case S_IFLNK:
      return .symlink
    case S_IFREG:
      return .file
    default:
      return .other
    }
  }

  private static let slash: UInt8 = 0x2F

  /// A name that is not UTF-8, written in ASCII: printable ASCII as it is, every other byte as
  /// `\xNN`.
  static func escaped(_ bytes: [UInt8]) -> String {
    var text = ""

    for byte in bytes {
      if byte >= 0x20, byte < 0x7F, byte != 0x5C {
        text.unicodeScalars.append(Unicode.Scalar(byte))
      } else {
        text += "\\x" + (byte < 0x10 ? "0" : "") + String(byte, radix: 16, uppercase: true)
      }
    }

    return text
  }

  /// The kind of a file that was there a moment ago, or `nil` when it has gone since.
  private func regularOrOther(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    let attributes: [FileAttributeKey: Any]

    do {
      attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    } catch {
      if Self.isMissing(error) {
        return nil
      }

      throw .unreadable(url, reason: error.localizedDescription)
    }

    guard let type = attributes[.type] as? FileAttributeType else {
      return .file
    }

    return type == .typeRegular ? .file : .other
  }

  private static func isMissing(_ error: any Error) -> Bool {
    if let cocoa = error as? CocoaError,
       cocoa.code == .fileNoSuchFile || cocoa.code == .fileReadNoSuchFile
    {
      return true
    }

    let missingCodes = [ENOENT, ENOTDIR].map(Int.init)
    let nsError = error as NSError

    if nsError.domain == NSPOSIXErrorDomain, missingCodes.contains(nsError.code) {
      return true
    }

    guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else {
      return false
    }

    return underlying.domain == NSPOSIXErrorDomain && missingCodes.contains(underlying.code)
  }
}
