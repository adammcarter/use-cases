import Foundation

/// Resolves a transformer reference: a bundled name is the `use-cases-transformers` program in
/// the folder of the running `use-cases`, found by its real path, and a program path is the
/// project's own file (chapter 10 §9, `docs/architecture.md` §6).
struct TransformerLocator: TransformerLocating {
  /// The one program the bundled transformers ship as.
  static let bundledProgramName = "use-cases-transformers"

  private let executable: any RunningExecutableLocating
  private let fileSystem: any FileSystemReading

  init(
    executable: any RunningExecutableLocating,
    fileSystem: any FileSystemReading,
  ) {
    self.executable = executable
    self.fileSystem = fileSystem
  }

  func command(
    for reference: TransformerReference,
    in root: URL,
  ) throws(TransformerError) -> [String] {
    switch reference {
    case let .program(path):
      [root.appendingPathComponent(path.text).path]
    case let .bundled(name):
      try [bundledProgram(for: name).path, name]
    }
  }

  private func bundledProgram(for name: String) throws(TransformerError) -> URL {
    let folder = executable.executableLocation().map { location in
      fileSystem.canonicalLocation(of: location).deletingLastPathComponent()
    }
    let program = folder?.appendingPathComponent(Self.bundledProgramName)

    guard
      let program,
      let kind = try? fileSystem.kindOfItem(at: program),
      kind == .file || kind == .symlink
    else {
      throw .programMissing(
        name: name,
        expectedAt: program?.path ?? Self.bundledProgramName,
      )
    }

    return program
  }
}
