import Foundation

/// A run of the built program to its end, with nothing to read: what it wrote to standard output
/// and how it ended, waited for without holding a thread.
struct AwaitedProgram {
  /// Everything it wrote to standard output.
  let output: String

  /// How it ended.
  let termination: ProcessTermination

  /// Runs `program` with `arguments` in `folder`, and returns once it has ended and its output
  /// has reached its end. Its standard error goes nowhere.
  static func run(
    _ program: URL,
    arguments: [String],
    folder: URL? = nil,
  ) async throws -> AwaitedProgram {
    let process = Process()
    let output = Pipe()
    process.executableURL = program
    process.arguments = arguments
    process.currentDirectoryURL = folder
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    let reader = OutputReader(
      output.fileHandleForReading,
      readSize: 65536,
    )
    let end = ProcessEnd(of: process)

    do {
      try process.run()
    } catch {
      try? reader.stop()

      throw error
    }

    var bytes: [UInt8] = []

    for await chunk in reader.chunks {
      bytes += chunk
    }

    return await AwaitedProgram(
      output: String(bytes: bytes, encoding: .utf8) ?? "",
      termination: end.termination(),
    )
  }
}
