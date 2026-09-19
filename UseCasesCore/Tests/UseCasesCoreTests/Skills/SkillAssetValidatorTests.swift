import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Skill-asset validation, against what the TypeScript's `validateSkillAssets`
/// returned or threw for the same workspace.
struct SkillAssetValidatorTests {
  @Test(arguments: SkillsGoldenCorpus.caseNames)
  func `skill assets validate as the TypeScript validated them`(caseName: String) throws {
    let testCase = try SkillsFixtures.testCase(caseName)
    let workspace = try SkillsFixtures.workspace(overlay: testCase["overlay"])
    let context = try workspace.context()

    let outcome: JSONValue
    do throws(SkillAssetValidationError) {
      outcome = try .object(JSONObject([
        ("result", SkillAssetValidator.validate(context: context).jsonValue),
      ]))
    } catch {
      outcome = .object(JSONObject([("thrown", .object(JSONObject([
        ("code", error.code.map(JSONValue.string) ?? .null),
        ("message", .string(error.message)),
      ])))]))
    }

    CapsulesFixtures.expectSame(outcome, testCase["outcome"], in: workspace, caseName)
  }
}

/// The canonical skill list.
struct CanonicalSkillTests {
  @Test
  func `the canonical skills are the TypeScript's, in its order`() throws {
    #expect(try CanonicalSkill.allCases.map(\.rawValue) == SkillsFixtures
      .strings("canonical_skills"))
  }
}

/// The CLI commands a skill body may name.
struct KnownCliCommandsTests {
  @Test(arguments: [
    ("known_cli_commands", KnownCliCommands.twoToken),
    ("known_flat_cli_commands", KnownCliCommands.flat),
    ("builtin_flat_cli_commands", KnownCliCommands.builtinFlat),
  ])
  func `each command list is the TypeScript's, in its order`(
    key: String,
    commands: [String],
  ) throws {
    #expect(try commands == SkillsFixtures.strings(key))
  }

  @Test(arguments: [
    ("matrix list", true),
    ("bind --repo", true),
    ("init", true),
    ("version x", true),
    ("migrate test-matrix", false),
    ("Matrix list", false),
    ("matrix", false),
    ("", false),
  ])
  func `a reference is known by its pair or its bare command`(
    command: String,
    isKnown: Bool,
  ) {
    #expect(KnownCliCommands.isKnown(command) == isKnown)
  }
}
