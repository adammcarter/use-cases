import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript run, replayed through the Swift CLI and compared
/// byte for byte: stdout, stderr, exit status and the config left on disk.
struct DispatchGoldenCorpusTests {
  @Test(arguments: DispatchGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI byte for byte`(caseName: String) throws {
    let recorded = try DispatchFixtures.testCase(caseName)
    let sandbox = try DispatchFixtures.Sandbox(recorded: recorded)

    let outcome = CommandLineInterface.run(arguments: sandbox.arguments)

    #expect(outcome.standardOutput == sandbox.expected("stdout"))
    #expect(outcome.standardError == sandbox.expected("stderr"))
    #expect(outcome.exitCode == sandbox.expectedStatus)
    #expect(sandbox.configurationAfter() == sandbox.expectedConfiguration)
  }
}
