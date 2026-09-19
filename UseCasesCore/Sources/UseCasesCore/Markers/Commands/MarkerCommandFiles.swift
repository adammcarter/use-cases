/// The ledger write the command cores share (io.ts).
public enum MarkerCommandFiles {
  /// `appendJsonlLine`: NOT an append. The whole file is read, a newline is
  /// added when the existing content lacks one, the line is added, and the
  /// WHOLE file is replaced through the atomic temp-and-rename write, with no
  /// lock. Two concurrent writers can each read the same state and the later
  /// rename wins; that is the TypeScript's behaviour, kept as it is.
  public static func appendJSONLine(
    _ line: String,
    toPath path: String,
    files: some MarkerFileSystem,
  ) throws(FileAccessError) {
    let existing = try files.readText(atPath: path) ?? ""
    let base = existing.utf16.isEmpty || existing.utf16.last == CodeUnits.lineFeed
      ? existing
      : existing + "\n"
    try files.writeText(base + line + "\n", toPath: path)
  }
}
