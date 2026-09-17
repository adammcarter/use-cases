import Foundation

/// What `lstatSync` says a directory entry is, in the three questions the
/// matrix walk asks of it.
enum NodeFileKind: Equatable {
  case symbolicLink
  case directory
  case regularFile
  case other
}

/// The filesystem calls the use-case matrix makes beyond reading and writing
/// text, failing as node's synchronous `fs` calls fail.
extension NodeFile {
  /// `readFileSync(path)`: the raw bytes, nothing decoded.
  static func readBytes(atPath path: String) throws(FileAccessError) -> [UInt8] {
    let descriptor = open(path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw FileAccessError(errorNumber: errno, operation: "open", path: path)
    }
    defer {
      close(descriptor)
    }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      let count = buffer.withUnsafeMutableBytes { raw in
        read(descriptor, raw.baseAddress, raw.count)
      }
      guard count >= 0 else {
        throw FileAccessError(errorNumber: errno, operation: "read", path: nil)
      }
      if count == 0 {
        return bytes
      }
      bytes.append(contentsOf: buffer[0 ..< count])
    }
  }

  /// `existsSync(path)`: true when `access(F_OK)` succeeds, following symlinks,
  /// and false for every failure.
  static func exists(atPath path: String) -> Bool {
    access(path, F_OK) == 0
  }

  /// `readdirSync(path)`: the entry names in libuv's `scandir` order, which is
  /// `strcmp` over their UTF-8 bytes.
  static func directoryNames(atPath path: String) throws(FileAccessError) -> [String] {
    guard let directory = opendir(path) else {
      throw FileAccessError(errorNumber: errno, operation: "scandir", path: path)
    }
    defer {
      closedir(directory)
    }
    var names: [String] = []
    while let entry = readdir(directory) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        let bytes = raw.prefix { byte in
          byte != 0
        }
        return UTF8Text.decodeReplacingInvalid(Array(bytes))
      }
      if name != ".", name != ".." {
        names.append(name)
      }
    }
    return names.sorted(by: JavaScriptStringOrder.byteAscending)
  }

  /// `lstatSync(path)`, reduced to what the entry is.
  static func kind(atPath path: String) throws(FileAccessError) -> NodeFileKind {
    var status = stat()
    guard lstat(path, &status) == 0 else {
      throw FileAccessError(errorNumber: errno, operation: "lstat", path: path)
    }
    switch status.st_mode & S_IFMT {
    case S_IFLNK: return .symbolicLink
    case S_IFDIR: return .directory
    case S_IFREG: return .regularFile
    default: return .other
    }
  }

  /// `realpathSync(path)`: every symlink resolved.
  static func realPath(_ path: String) throws(FileAccessError) -> String {
    guard let resolved = realpath(path, nil) else {
      throw FileAccessError(errorNumber: errno, operation: "realpath", path: path)
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }
}
