import Foundation

/// File operations that fail the way node's synchronous `fs` calls fail, so
/// the error text a caller embeds is node's.
enum NodeFile {
  /// `readFileSync(path, "utf8")`: invalid bytes replaced, a byte-order mark
  /// kept.
  static func readText(atPath path: String) throws(FileAccessError) -> String {
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
        return UTF8Text.decodeReplacingInvalid(bytes)
      }
      bytes.append(contentsOf: buffer[0 ..< count])
    }
  }

  /// `writeFileSync(path, text)`: created or truncated, mode 0666 before umask.
  static func writeText(
    _ text: String,
    atPath path: String,
  ) throws(FileAccessError) {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
    guard descriptor >= 0 else {
      throw FileAccessError(errorNumber: errno, operation: "open", path: path)
    }
    defer {
      close(descriptor)
    }
    var bytes = Array(text.utf8)[...]
    while !bytes.isEmpty {
      let written = bytes.withUnsafeBytes { raw in
        write(descriptor, raw.baseAddress, raw.count)
      }
      guard written >= 0 else {
        throw FileAccessError(errorNumber: errno, operation: "write", path: nil)
      }
      bytes = bytes.dropFirst(written)
    }
  }

  /// `mkdirSync(path, { recursive: true })`. A failure names the path that was
  /// asked for, not the component that failed, as node's does.
  static func makeDirectories(atPath path: String) throws(FileAccessError) {
    var prefix = path.hasPrefix("/") ? "" : "."
    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
      prefix += "/\(component)"
      guard mkdir(prefix, 0o777) != 0 else {
        continue
      }
      let failure = errno
      var status = stat()
      if failure == EEXIST, stat(prefix, &status) == 0, status.st_mode & S_IFMT == S_IFDIR {
        continue
      }
      // An existing FILE partway down the path is a component that is not a
      // directory; only the final component reports that it already exists.
      let reported = failure == EEXIST && prefix != path ? ENOTDIR : failure
      throw FileAccessError(errorNumber: reported, operation: "mkdir", path: path)
    }
  }
}

/// A libuv filesystem error, spelled as node spells its message:
/// `ENOENT: no such file or directory, open '<path>'`.
public struct FileAccessError: Error, Equatable, Sendable {
  let errorNumber: Int32
  let operation: String
  let path: String?
  let destination: String?

  init(
    errorNumber: Int32,
    operation: String,
    path: String?,
    destination: String? = nil,
  ) {
    self.errorNumber = errorNumber
    self.operation = operation
    self.path = path
    self.destination = destination
  }

  /// The errno name, e.g. `ENOENT`.
  public var code: String {
    switch errorNumber {
    case ENOENT: "ENOENT"
    case EACCES: "EACCES"
    case EISDIR: "EISDIR"
    case ENOTDIR: "ENOTDIR"
    case EEXIST: "EEXIST"
    default: "E\(errorNumber)"
    }
  }

  public var message: String {
    let description = switch errorNumber {
    case ENOENT: "no such file or directory"
    case EACCES: "permission denied"
    case EISDIR: "illegal operation on a directory"
    case ENOTDIR: "not a directory"
    case EEXIST: "file already exists"
    default: String(cString: strerror(errorNumber)).lowercased()
    }
    guard let path else {
      return "\(code): \(description), \(operation)"
    }
    guard let destination else {
      return "\(code): \(description), \(operation) '\(path)'"
    }
    return "\(code): \(description), \(operation) '\(path)' -> '\(destination)'"
  }
}
