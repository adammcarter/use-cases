import ArgumentParser
import Foundation

/// The process entry point, on swift-argument-parser.
///
/// The TypeScript CLI's argument semantics cannot be expressed as declared
/// options: flags match exact tokens only (no `--flag=value`), a value-bearing
/// flag consumes the next token even when it looks like a flag, help and
/// version count anywhere, and `--` separates a payload. So the library is used
/// for the entry alone, with its own help, version and completion flags out of
/// the way, and every raw argument is forwarded to ``CommandLineInterface``,
/// which ports the TypeScript parser as it is.
public struct UseCasesCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "uc",
    helpNames: [],
  )

  /// The raw arguments, after the separator ``main()`` puts in front of them.
  @Argument(parsing: .captureForPassthrough)
  var arguments: [String] = []

  public init() {}

  /// Parse the process arguments with everything behind a leading `--`, so the
  /// library reads them all as values and none as its own flags.
  public static func main() async {
    await main(forwardedPrefix + CommandLine.arguments.dropFirst())
  }

  public func run() async throws {
    let outcome = await CommandLineInterface.run(arguments: Self.stripped(arguments))
    FileHandle.standardOutput.write(Data(outcome.standardOutput.utf8))
    FileHandle.standardError.write(Data(outcome.standardError.utf8))
    guard outcome.exitCode == 0 else {
      throw ExitCode(outcome.exitCode)
    }
  }

  /// What the CLI receives for `raw` once the library has parsed it.
  static func forwardedArguments(_ raw: [String]) throws -> [String] {
    try stripped(parse(forwardedPrefix + raw).arguments)
  }

  private static let forwardedPrefix = ["--"]

  private static func stripped(_ parsed: [String]) -> [String] {
    parsed.first == "--" ? Array(parsed.dropFirst()) : parsed
  }
}
