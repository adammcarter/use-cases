import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript `init` and `matrix` run, replayed through the
/// Swift CLI and compared byte for byte: stdout, stderr, exit status, every
/// file left in the sandbox and git's core.hooksPath afterwards.
struct MatrixInitGoldenCorpusTests {
  @Test(arguments: MatrixInitGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI and its files byte for byte`(caseName: String) async throws {
    let recorded = try MatrixInitFixtures.testCase(caseName)
    let sandbox = try MatrixInitFixtures.Sandbox(recorded: recorded)

    let outcome = await CommandLineInterface.run(
      arguments: sandbox.arguments,
      environment: MatrixInitFixtures.isolatedEnvironment,
    )

    let expectedOutput = sandbox.expected("stdout")
    if MatrixInitFixtures.carriesParserWording(expectedOutput) {
      #expect(
        MatrixInitFixtures.masked(outcome.standardOutput)
          == MatrixInitFixtures.masked(expectedOutput),
      )
    } else {
      #expect(outcome.standardOutput == expectedOutput)
    }
    #expect(outcome.standardError == sandbox.expected("stderr"))
    #expect(outcome.exitCode == sandbox.expectedStatus)
    #expect(try sandbox.tree() == sandbox.expectedTree)
    #expect(sandbox.configuredHooksPath() == sandbox.expectedHooksPath)
  }

  @Test(arguments: [
    (
      #"{"diagnostics":[{"code":"parse_error","message":"Unexpected end"}]}"# + "\n",
      #"{"diagnostics":[{"code":"parse_error","message":"<parser message>"}]}"# + "\n",
    ),
    (
      #"{"diagnostics":[{"code":"other","message":"kept"}]}"# + "\n",
      #"{"diagnostics":[{"code":"other","message":"kept"}]}"# + "\n",
    ),
    (
      "  \u{2717} parse_error: Flow sequence\n      at use-cases/bad.yaml\n",
      "  \u{2717} parse_error: <parser message>\n      at use-cases/bad.yaml\n",
    ),
    (
      "\u{2717} matrix.upsert\n\n  \u{2717} matrix.mutation_invalid_json: Unexpected token\n",
      "\u{2717} matrix.upsert\n\n  \u{2717} matrix.mutation_invalid_json: <parser message>\n",
    ),
  ])
  func `masks only parser-worded messages`(
    input: String,
    expected: String,
  ) {
    #expect(MatrixInitFixtures.masked(input) == expected)
  }
}
