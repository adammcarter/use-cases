import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// `use-cases init`'s scaffolding, against what the TypeScript's `scaffoldWorkspace`
/// returned, threw and left on disk for the same sandbox.
struct WorkspaceScaffoldTests {
  //: @use-case:plugin.init.wires_git_hooks
  @Test(arguments: InitializationGoldenCorpus.caseNames)
  func `a workspace is scaffolded as the TypeScript scaffolded it`(caseName: String) throws {
    let testCase = try InitializationFixtures.testCase(caseName)
    let setup = try #require(testCase["setup"])
    let sandbox = try InitializationFixtures.Sandbox(setup: setup)
    let options = try Self.options(testCase["options"], repositoryRoot: sandbox.repositoryRoot)
    let git = setup["git_missing"]?.boolValue == true
      ? ScaffoldGitProcessRunner(environment: [
        "PATH": "/nonexistent-use-cases-corpus-path",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
      ])
      : InitializationFixtures.isolatedGit

    let outcome: JSONValue
    do throws(WorkspaceScaffoldError) {
      let result = try WorkspaceScaffold.scaffold(
        options,
        git: git,
        clock: FixedInitializationClock(milliseconds: 0),
      )
      outcome = .object(JSONObject([("result", result.jsonValue)]))
    } catch {
      outcome = .object(JSONObject([("thrown", .object(JSONObject([
        ("code", .string(error.code)),
        ("message", .string(error.message)),
      ])))]))
    }

    let expectedOutcome = try #require(testCase["outcome"])
    #expect(
      InitializationFixtures.wire(outcome)
        .replacingOccurrences(of: sandbox.repositoryRoot, with: "<repo>")
        == InitializationFixtures.wire(expectedOutcome),
    )
    #expect(try InitializationFixtures.wire(sandbox.tree()) == InitializationFixtures
      .wire(testCase["tree"]))
    let expectedHooksPath = testCase["hooks_path_after"]?.stringValue
    let hooksPath = setup["git"]?.boolValue == true ? sandbox.configuredHooksPath() : nil
    #expect(hooksPath == expectedHooksPath)
  }

  //: @use-case:end plugin.init.wires_git_hooks

  @Test
  func `the templates are the TypeScript's, in its order`() throws {
    let templates = try #require(InitializationFixtures.corpus.get()["templates"]?.arrayValue)
    #expect(InitializationTemplate.allCases.map(\.rawValue) == templates.compactMap(\.stringValue))
    #expect(InitializationTemplate(rawValue: "js-jest") == nil)
  }

  @Test(arguments: 0 ..< 5)
  func `next steps mention hooksPath only when unset on the default directory`(index: Int) throws {
    let entries = try #require(InitializationFixtures.corpus.get()["next_steps"]?.arrayValue)
    let entry = try #require(entries.count > index ? entries[index] : nil)
    let options = try #require(entry["options"])

    let steps = WorkspaceScaffold.nextSteps(
      hooksPathSet: options["hooksPathSet"]?.boolValue,
      hooksDirectory: options["hooksDir"]?.stringValue,
    )

    #expect(InitializationFixtures
      .wire(.array(steps.map(JSONValue.string))) == InitializationFixtures
      .wire(entry["steps"]))
  }

  //: @use-case:plugin.init.records_decision_in_agents_md
  @Test(arguments: 0 ..< 7)
  func `the AGENTS decision is dated from the clock when no day is given`(index: Int) throws {
    let entries = try #require(InitializationFixtures.corpus.get()["today_from_clock"]?.arrayValue)
    let entry = try #require(entries.count > index ? entries[index] : nil)
    let milliseconds = try #require(entry["milliseconds"]?.numberValue)
    let today = try #require(entry["today"]?.stringValue)
    let directory = try TemporaryDirectory()
    let repositoryRoot = try directory.makeDirectory("dated").path

    _ = try WorkspaceScaffold.scaffold(
      WorkspaceScaffoldOptions(repositoryRoot: repositoryRoot),
      git: InitializationFixtures.isolatedGit,
      clock: FixedInitializationClock(milliseconds: milliseconds),
    )

    let agents = try String(contentsOfFile: repositoryRoot + "/AGENTS.md", encoding: .utf8)
    #expect(agents
      .split(separator: "\n", omittingEmptySubsequences: false)[4] == "yes \u{2014} \(today)")
  }

  //: @use-case:end plugin.init.records_decision_in_agents_md

  @Test
  func `a relative repository root resolves against the given working directory`() throws {
    let directory = try TemporaryDirectory()
    _ = try directory.makeDirectory("work")

    let result = try WorkspaceScaffold.scaffold(
      WorkspaceScaffoldOptions(
        repositoryRoot: "../relative-repo",
        today: InitializationFixtures.today,
      ),
      git: InitializationFixtures.isolatedGit,
      clock: FixedInitializationClock(milliseconds: 0),
      currentDirectory: directory.url.appendingPathComponent("work").path,
    )

    #expect(result.componentIdentifier == "relative-repo")
    #expect(FileManager.default
      .fileExists(atPath: directory.url.path + "/relative-repo/use-cases.yml"))
  }

  private static func options(
    _ value: JSONValue?,
    repositoryRoot: String,
  ) throws -> WorkspaceScaffoldOptions {
    let template = try value?["template"]?.stringValue.map { raw in
      try #require(InitializationTemplate(rawValue: raw))
    }
    return WorkspaceScaffoldOptions(
      repositoryRoot: repositoryRoot,
      template: template,
      component: value?["component"]?.stringValue,
      force: value?["force"]?.boolValue ?? false,
      today: value?["today"]?.stringValue,
    )
  }
}

/// The git process init runs, against real repositories and a real directory
/// that is not one.
struct ScaffoldGitProcessRunnerTests {
  @Test
  func `git inside a repository exits zero with its output`() throws {
    let directory = try TemporaryDirectory()
    let git = InitializationFixtures.isolatedGit
    #expect(git.run(["init", "-q"], workingDirectory: directory.url.path).exitStatus == 0)

    let outcome = git.run(["rev-parse", "--git-dir"], workingDirectory: directory.url.path)

    #expect(outcome.exitStatus == 0)
    #expect(outcome.standardOutput == ".git\n")
  }

  @Test
  func `git outside a repository exits non-zero`() throws {
    let directory = try TemporaryDirectory()

    let outcome = InitializationFixtures.isolatedGit.run(
      ["rev-parse", "--git-dir"],
      workingDirectory: directory.url.path,
    )

    #expect(outcome.exitStatus == 128)
    #expect(outcome.standardOutput.isEmpty)
  }

  @Test(arguments: [["PATH": "/nonexistent-use-cases-corpus-path"], ["PATH": ""]])
  func `git that is not on PATH never runs`(environment: [String: String]) throws {
    let directory = try TemporaryDirectory()

    let outcome = ScaffoldGitProcessRunner(environment: environment)
      .run(["rev-parse", "--git-dir"], workingDirectory: directory.url.path)

    #expect(outcome.exitStatus == nil)
    #expect(outcome.standardOutput.isEmpty)
  }
}
