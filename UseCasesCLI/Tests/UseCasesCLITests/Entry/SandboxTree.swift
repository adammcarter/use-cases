import Foundation
import Testing
import UseCasesCore

/// A sandbox directory listed the way the corpus generators list one: every
/// entry except `.git` directories, in UTF-16 code-unit order, each file with
/// its mode and contents.
enum SandboxTree {
  /// The listing as the wire JSON the generators record.
  static func listing(root: String) throws -> String {
    var entries: [(path: String, value: JSONValue)] = []
    try walk(root: root, relativeDirectory: "", into: &entries)
    entries.sort { left, right in
      left.path.utf16.lexicographicallyPrecedes(right.path.utf16)
    }
    return JSONWriter.encode(.array(entries.map(\.value)))
  }

  /// `path` with every symlink resolved, or `path` itself when it cannot be.
  static func realpathOf(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
      return path
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }

  /// readdir(3)'s names, exactly as stored.
  private static func names(in directory: String) throws -> [String] {
    let stream = try #require(opendir(directory))
    defer {
      closedir(stream)
    }
    var names: [String] = []
    while let entry = readdir(stream) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
      }
      if name != ".", name != ".." {
        names.append(name)
      }
    }
    return names
  }

  private static func walk(
    root: String,
    relativeDirectory: String,
    into entries: inout [(path: String, value: JSONValue)],
  ) throws {
    let absoluteDirectory = relativeDirectory.isEmpty ? root : root + "/" + relativeDirectory
    for name in try names(in: absoluteDirectory) where name != ".git" {
      let path = relativeDirectory.isEmpty ? name : relativeDirectory + "/" + name
      let absolutePath = root + "/" + path
      var status = stat()
      try #require(lstat(absolutePath, &status) == 0)
      switch status.st_mode & S_IFMT {
      case S_IFLNK:
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: absolutePath)
        entries.append((path, .object(JSONObject([
          ("path", .string(path)),
          ("kind", .string("symlink")),
          ("target", .string(target)),
        ]))))
      case S_IFDIR:
        entries.append((path, .object(JSONObject([
          ("path", .string(path)),
          ("kind", .string("directory")),
        ]))))
        try walk(root: root, relativeDirectory: path, into: &entries)
      default:
        let content = try NodeFile.readText(atPath: absolutePath)
        entries.append((path, .object(JSONObject([
          ("path", .string(path)),
          ("kind", .string("file")),
          ("mode", .string(String(status.st_mode & 0o777, radix: 8))),
          ("content", .string(content)),
        ]))))
      }
    }
  }
}
