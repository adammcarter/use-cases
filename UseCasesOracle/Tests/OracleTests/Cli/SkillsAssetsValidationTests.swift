import Foundation
import Testing

//: @use-case:skills.assets.asset_validation#blackbox
/// The black-box oracle for two remaining rows of skills/assets.yml:
/// asset_validation and degraded_assets.
///
/// `SkillsAssetsTests` already covers host_declaration and
/// unreachable_skills_fail_doctor. demo_gates lives in
/// tests/skills/p7-skills.test.ts per its own verifier and is left alone here.
///
/// The fixture is ``ShippedPluginCopy``, shared with that file. In TypeScript
/// each oracle file carried its own byte-identical `makePluginCopy`; a Swift
/// test target is one module with one namespace, so the two copies became one
/// helper. It builds the layout and nothing else — no assertions, no
/// expectations about a row — so an edit to it cannot quietly restate what a
/// row promises.
struct SkillsAssetsValidationTests {
  static func doctor(_ directory: TemporaryDirectory) async throws -> CliBinary.JsonOutcome {
    try await ShippedPluginCopy.doctor(
      directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func skillPaths(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["skills"]?.arrayValue ?? []).compactMap { skill in
      skill["path"]?.stringValue
    }
  }

  // golden_doctor. Every shipped skill is discovered, each with a name, path,
  // description and a complete: true front-matter check.
  @Test
  func `an intact checkout discovers every shipped skill with intact assets`()
    async throws
  {
    let doctored = try await Self.doctor(ShippedPluginCopy.make("skills-assets"))

    #expect(doctored.isOk == true)
    let count = try #require(doctored.data["skill_count"]?.intValue)
    #expect(count > 0)
    let skills = doctored.data["skills"]?.arrayValue ?? []
    #expect(skills.count == count)
    for skill in skills {
      let name = skill["name"]?.stringValue ?? ""
      #expect(!name.isEmpty, "every skill has a discovered name")
      // Bound first: `#expect(!(x?.y ?? "").isEmpty)` expands to a
      // property-access check on the OPTIONAL and reports a false failure.
      let description = skill["description"]?.stringValue ?? ""
      #expect(
        !description.isEmpty,
        Comment(rawValue: "\(name) has a real description"),
      )
      #expect(skill["complete"]?.boolValue == true, Comment(rawValue: "\(name) reports valid"))
    }
    #expect(doctored.diagnosticCodes.isEmpty)
  }

  // bad_required_file_missing. Removing a skill's SKILL.md — the file that
  // makes it a skill at all — must stop it from validating clean.
  //
  // MEASURED: with the directory left in place, the loader silently skips
  // the skill (it drops out of `skills[]`/`skill_count` entirely) rather than
  // emitting a dedicated "file missing" diagnostic for it. The result still
  // fails overall (ok:false, complete:false) via `skills.host_not_declared`,
  // because a Claude host can no longer find SKILL.md under every canonical
  // skill name — that IS how "cannot be published while required files are
  // missing" actually shows up here.
  @Test
  func `a skill whose SKILL md is removed can no longer be published clean`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills-assets")
    let before = try await Self.doctor(directory)
    let countBefore = try #require(before.data["skill_count"]?.intValue)
    #expect(countBefore > 0)
    #expect(ShippedPluginCopy.skillNames(before).contains("init"))

    try directory.remove("skills/init/SKILL.md")

    let doctored = try await Self.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.data["complete"]?.boolValue == false)
    #expect(doctored.data["skill_count"]?.intValue == countBefore - 1)
    #expect(!ShippedPluginCopy.skillNames(doctored).contains("init"))
    #expect(
      !doctored.diagnosticCodes.isEmpty,
      "the failure is reported as a diagnostic, not silence",
    )
  }

  // edge_front_matter_name_matches_the_directory. Every discovered skill's
  // name is exactly its directory: that is the identifier a host will use to
  // address it, so the two must never drift apart.
  @Test
  func `every discovered skill's name is the directory the host addresses it by`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills-assets")
    let doctored = try await Self.doctor(directory)
    for skill in doctored.data["skills"]?.arrayValue ?? [] {
      let name = try #require(skill["name"]?.stringValue)
      #expect(skill["path"]?.stringValue == "skills/\(name)/SKILL.md")
    }
    #expect(!doctored.diagnosticCodes.contains("skills.name_mismatch"))

    // Break the correspondence deliberately: point one skill's frontmatter
    // name away from its own directory.
    let original = try directory.readFile("skills/init/SKILL.md")
    try directory.writeFile(
      "skills/init/SKILL.md",
      contents: original.replacingOccurrences(
        of: "\nname: init\n",
        with: "\nname: not-init\n",
      ),
    )

    let broken = try await Self.doctor(directory)
    #expect(broken.diagnosticCodes.contains("skills.name_mismatch"))
    let entry = (broken.data["skills"]?.arrayValue ?? []).first { skill in
      skill["path"]?.stringValue == "skills/init/SKILL.md"
    }
    #expect(
      entry?["name"]?.stringValue == "not-init",
      "the discovered name follows the frontmatter, so a mismatch is visible here",
    )
  }
}

//: @use-case:end skills.assets.asset_validation#blackbox

//: @use-case:skills.assets.degraded_assets#blackbox
/// The black-box oracle for skills/assets.yml, row `degraded_assets`.
struct SkillsAssetsDegradedTests {
  /// Corrupt the opening frontmatter delimiter so no YAML block is found.
  static func damageInitFrontmatter(_ directory: TemporaryDirectory) throws {
    let original = try directory.readFile("skills/init/SKILL.md")
    guard let range = original.range(of: "---\n") else {
      return
    }
    try directory.writeFile(
      "skills/init/SKILL.md",
      contents: original.replacingCharacters(in: range, with: "XXX\n"),
    )
  }

  // golden_report. A skill missing a required asset (its SKILL.md) is
  // reported with a diagnostic rather than silently omitted from the result.
  @Test
  func `a skill missing its required asset is reported with a diagnostic`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills-assets")
    try directory.remove("skills/walkthrough/SKILL.md")

    let doctored = try await SkillsAssetsValidationTests.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(!doctored.diagnosticCodes.isEmpty)
    #expect(!ShippedPluginCopy.skillNames(doctored).contains("walkthrough"))
  }

  // bad_damage_is_never_reported_as_healthy. Malformed front-matter (no YAML
  // block at all) must never pass as a healthy skill.
  @Test
  func `malformed front-matter never passes as healthy`() async throws {
    let directory = try ShippedPluginCopy.make("skills-assets")
    try Self.damageInitFrontmatter(directory)

    let doctored = try await SkillsAssetsValidationTests.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.diagnosticCodes.contains("skills.frontmatter_missing"))
    let entry = (doctored.data["skills"]?.arrayValue ?? []).first { skill in
      skill["path"]?.stringValue == "skills/init/SKILL.md"
    }
    let damaged = try #require(entry, "the damaged skill still appears in the list")
    #expect(damaged["complete"]?.boolValue == false, "but never marked complete")
  }

  // edge_one_damaged_skill_does_not_hide_the_rest. One skill's malformed
  // front-matter must not swallow the report on the other skills, and the
  // process must exit with a plain nonzero status rather than crashing.
  @Test
  func `one damaged skill does not hide the others, and the run is non-fatal`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills-assets")
    try Self.damageInitFrontmatter(directory)

    let doctored = try await SkillsAssetsValidationTests.doctor(directory)
    #expect(doctored.exitCode == 1, "a normal refusal exit code, not a crash")
    let others = (doctored.data["skills"]?.arrayValue ?? []).filter { skill in
      skill["path"]?.stringValue != "skills/init/SKILL.md"
    }
    #expect(!others.isEmpty)
    for skill in others {
      #expect(
        skill["complete"]?.boolValue == true,
        Comment(
          rawValue: "\(skill["name"]?.stringValue ?? "?") stays healthy despite init's damage",
        ),
      )
    }
  }
}

//: @use-case:end skills.assets.degraded_assets#blackbox
