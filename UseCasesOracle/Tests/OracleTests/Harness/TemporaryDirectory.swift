import Foundation

/// A real on-disk directory that deletes itself when the last reference goes away.
///
/// The same type `TestSupport` vends to the white-box suites, copied rather than
/// imported: the oracle links nothing (see `Package.swift`), and forty lines is
/// a cheaper price than a dependency that has to survive row 10d.
///
/// The `mkdtempSync(join(tmpdir(), …))` every black-box file opens with is this.
final class TemporaryDirectory: Sendable {
  let url: URL

  var path: String {
    url.path
  }

  init(_ label: String = "oracle") throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("use-cases-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    // Note the direction: `resolvingSymlinksInPath()` STRIPS `/private`, giving
    // `/var/folders/…`, while `realpath(3)` — what Node's `realpathSync`
    // answers, and so what the product's own containment checks match — gives
    // `/private/var/folders/…`. A test comparing a path STRING against product
    // output must resolve it the same way first.
    url = URL(fileURLWithPath: base.path).resolvingSymlinksInPath()
  }

  /// What `realpath(3)` answers — which is what Node's `realpathSync` answers,
  /// and so what a product process reports as its own working directory.
  /// `resolvingSymlinksInPath()` is NOT the same: it strips `/private`.
  var realPath: String {
    guard let resolved = realpath(url.path, nil) else {
      return url.path
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  @discardableResult
  func makeDirectory(_ relativePath: String) throws -> URL {
    let target = url.appendingPathComponent(relativePath, isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    return target
  }

  @discardableResult
  func writeFile(
    _ relativePath: String,
    contents: String,
  ) throws -> URL {
    let target = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try contents.write(to: target, atomically: true, encoding: .utf8)
    return target
  }

  @discardableResult
  func appendFile(
    _ relativePath: String,
    contents: String,
  ) throws -> URL {
    let target = url.appendingPathComponent(relativePath)
    let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
    return try writeFile(relativePath, contents: existing + contents)
  }

  /// An executable shell script, for the fake binaries and stub verifiers the
  /// oracle needs.
  @discardableResult
  func writeScript(
    _ relativePath: String,
    body: String,
  ) throws -> URL {
    let target = try writeFile(relativePath, contents: "#!/bin/sh\n\(body)\n")
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o755))],
      ofItemAtPath: target.path,
    )
    return target
  }

  /// Copy a file or tree in from anywhere, e.g. the shipped plugin layout.
  func copyIn(
    _ sourcePath: String,
    to relativePath: String,
  ) throws {
    let target = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try FileManager.default.copyItem(atPath: sourcePath, toPath: target.path)
  }

  /// Copy in if it is there, ignore it if it is not.
  func copyInIfPresent(
    _ sourcePath: String,
    to relativePath: String,
  ) {
    try? copyIn(sourcePath, to: relativePath)
  }

  func remove(_ relativePath: String) throws {
    try FileManager.default.removeItem(at: url.appendingPathComponent(relativePath))
  }

  func readFile(_ relativePath: String) throws -> String {
    try String(contentsOf: url.appendingPathComponent(relativePath), encoding: .utf8)
  }

  func exists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
  }

  @discardableResult
  func makeSymlink(
    _ relativePath: String,
    to destination: URL,
  ) throws -> URL {
    let link = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    return link
  }

  /// Every file beneath `relativePath`, recursively, as paths relative to it.
  func files(under relativePath: String) -> [String] {
    let root = url.appendingPathComponent(relativePath, isDirectory: true)
    guard let walker = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
    ) else {
      return []
    }
    // Both sides are resolved before the prefix is trimmed: the enumerator
    // answers `/private/var/...` while `root.path` is `/var/...`, and an
    // untrimmed prefix silently yields absolute paths that compare equal to
    // nothing a caller expects.
    let prefix = root.resolvingSymlinksInPath().path + "/"
    var found: [String] = []
    for case let entry as URL in walker {
      let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
      if isDirectory == true {
        continue
      }
      let resolved = entry.resolvingSymlinksInPath().path
      found.append(
        resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : resolved,
      )
    }
    return found.sorted()
  }
}
