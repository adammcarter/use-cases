import Foundation
import Testing

/// The built `use-cases` binary, run as a real process.
///
/// The cross-process append lock cannot be exercised inside this process: one
/// test host is one process, whatever its concurrency. So the void race runs
/// the binary itself, which the test target depends on so it is always built
/// alongside these tests.
///
/// Starting and waiting are separate (``started(arguments:environment:outputDirectory:label:)``
/// then ``UseCasesProcess/outcome()``) so a caller can have every process
/// running before it waits for any of them. Awaiting each start in turn would
/// let one run finish before the next began, and a race nobody runs
/// concurrently proves nothing.
struct UseCasesBinary {
  let path: String

  /// The binary next to the test bundle, or next to a products directory
  /// Xcode named.
  static func located() throws -> UseCasesBinary {
    let bundles = Bundle.allBundles.map(\.bundlePath).filter { bundle in
      bundle.hasSuffix(".xctest")
    }
    let named = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? ""
    let directories = bundles.map { bundle in
      (bundle as NSString).deletingLastPathComponent
    } + named.split(separator: " ").map(String.init)
    let path = directories
      .map { directory in directory + "/use-cases" }
      .first { candidate in
        FileManager.default.isExecutableFile(atPath: candidate)
      }
    return try UseCasesBinary(
      path: #require(path, "no built use-cases binary beside \(directories)"),
    )
  }

  /// Start one run. Both streams go to files under `outputDirectory`, so no
  /// pipe can fill while the process runs and nothing needs reading until it
  /// is over.
  func started(
    arguments: [String],
    environment: [String: String],
    outputDirectory: String,
    label: String,
  ) throws -> UseCasesProcess {
    let outputPath = "\(outputDirectory)/\(label).out"
    let errorPath = "\(outputDirectory)/\(label).err"
    for path in [outputPath, errorPath] {
      try #require(FileManager.default.createFile(atPath: path, contents: nil))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = try FileHandle(forWritingTo: URL(fileURLWithPath: outputPath))
    process.standardError = try FileHandle(forWritingTo: URL(fileURLWithPath: errorPath))
    let (terminations, termination) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { finished in
      termination.yield(finished.terminationStatus)
      termination.finish()
    }
    try process.run()
    return UseCasesProcess(
      terminations: terminations,
      outputPath: outputPath,
      errorPath: errorPath,
    )
  }

  /// Start one run and wait for it.
  func run(
    arguments: [String],
    environment: [String: String],
    outputDirectory: String,
    label: String,
  ) async throws -> UseCasesProcess.Outcome {
    try await started(
      arguments: arguments,
      environment: environment,
      outputDirectory: outputDirectory,
      label: label,
    ).outcome()
  }

  /// What every run in these tests is given: PATH, HOME, and profiling off —
  /// the Debug binary is instrumented, and eight processes writing one
  /// `default.profraw` would race over that instead.
  static func environment(home: String) -> [String: String] {
    [
      "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
      "HOME": home,
      "LLVM_PROFILE_FILE": "/dev/null",
    ]
  }
}
