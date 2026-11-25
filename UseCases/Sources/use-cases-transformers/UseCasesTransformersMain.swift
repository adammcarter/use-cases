import Foundation
import UseCasesTransformers

@main
struct UseCasesTransformersMain {
  /// Wiring only: the program itself is tested in UseCasesTransformers.
  static let program = TransformerProgram()

  static func main() {
    let outcome = program.run(arguments: Array(CommandLine.arguments.dropFirst()))

    if let message = outcome.message {
      FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    exit(outcome.exitCode)
  }
}
