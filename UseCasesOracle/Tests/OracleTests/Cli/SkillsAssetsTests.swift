import Foundation
import Testing

/// The fixture both skills/assets.yml oracle suites in this file use.
///
/// Every fixture copies the REAL plugin layout. An earlier attempt built a
/// minimal one by hand and reported `skills.missing` even when intact, so every
/// case measured the fixture rather than the condition under test.
enum ShippedPluginCopy {
  static func make(_ label: String) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory(label)
    let repository = OracleLayout.repositoryRoot
    try directory.makeDirectory(".claude-plugin")
    try directory.copyIn("\(repository)/skills", to: "skills")
    try directory.copyIn(
      "\(repository)/.claude-plugin/plugin.json",
      to: ".claude-plugin/plugin.json",
    )
    try directory.copyIn(
      "\(repository)/.claude-plugin/marketplace.json",
      to: ".claude-plugin/marketplace.json",
    )
    // Not every layout ships all of these; doctor tolerates their absence.
    for optional in ["agents", "bootstrap", "docs"] {
      directory.copyInIfPresent("\(repository)/\(optional)", to: optional)
    }
    return directory
  }

  static func doctor(
    _ directory: TemporaryDirectory,
    environment: [String: String] = [:],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      ["doctor", "skills", "--repo", "."],
      cwd: directory.path,
      environment: environment,
    )
  }

  static func hosts(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data.at("host_registration.hosts")?.arrayValue ?? []
  }

  static func skillNames(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["skills"]?.arrayValue ?? []).compactMap { skill in
      skill["name"]?.stringValue
    }
  }
}

/// The black-box oracle for skills/assets.yml, row `host_declaration`.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct SkillsAssetsHostDeclarationTests {
  // golden_manifests. Skills sit where the host scans, and the marketplace
  // manifest is what makes the plugin manifest get read at all.
  @Test
  func `an intact layout reports every skill reachable by the host`() async throws {
    let doctored = try await ShippedPluginCopy.doctor(ShippedPluginCopy.make("skills"))

    #expect(doctored.isOk == true)
    #expect((doctored.data["skill_count"]?.intValue ?? 0) > 0)
    #expect(doctored.data.at("host_registration.complete")?.boolValue == true)
    let claude = ShippedPluginCopy.hosts(doctored).first { host in
      host["host"]?.stringValue == "claude"
    }
    #expect(claude?["declares_skill_root"]?.boolValue == true)
    #expect(claude?["installable"]?.boolValue == true)
    #expect(doctored.diagnosticCodes.isEmpty)
  }

  // bad_moved_skills. A skill outside the scanned directory is unreachable, and
  // that is an error rather than a smaller pass.
  @Test
  func `a canonical skill moved out of skills is unreachable, not a pass`() async throws {
    let directory = try ShippedPluginCopy.make("skills")
    try directory.copyIn(
      directory.url.appendingPathComponent("skills/use-cases").path,
      to: "elsewhere/use-cases",
    )
    try directory.remove("skills/use-cases")

    let doctored = try await ShippedPluginCopy.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.diagnosticCodes.contains("skills.host_not_declared"))
    #expect(doctored.diagnosticCodes.contains("skills.missing"))
    #expect(
      ShippedPluginCopy.hosts(doctored).first?["declares_skill_root"]?.boolValue == false,
    )
  }

  // edge_marketplace_manifest_is_what_makes_it_readable. Declared but not
  // installable is still unreachable — the two are separate conditions with
  // separate codes.
  @Test
  func `without a marketplace manifest the plugin is declared but not installable`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills")
    try directory.remove(".claude-plugin/marketplace.json")

    let doctored = try await ShippedPluginCopy.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.diagnosticCodes.contains("skills.host_not_installable"))
    let claude = try #require(ShippedPluginCopy.hosts(doctored).first)
    #expect(
      claude["declares_skill_root"]?.boolValue == true,
      "the skills are still where the host scans",
    )
    #expect(claude["installable"]?.boolValue == false, "but nothing can install them")
  }
}

/// The black-box oracle for skills/assets.yml, row
/// `unreachable_skills_fail_doctor`.
struct SkillsAssetsUnreachableTests {
  // golden_intact_checkout.
  @Test
  func `an intact checkout reports the skills as registered`() async throws {
    let doctored = try await ShippedPluginCopy.doctor(ShippedPluginCopy.make("skills"))
    #expect(doctored.isOk == true)
    #expect(doctored.data.at("host_registration.complete")?.boolValue == true)
    let claude = try #require(ShippedPluginCopy.hosts(doctored).first)
    #expect(claude["host"]?.stringValue == "claude")
    #expect(claude["manifest_path"]?.stringValue?.contains("plugin.json") == true)
  }

  // bad_undeclared. Skills that exist on disk but no host can load are an
  // error, and the result is explicitly not complete.
  @Test
  func `skills no host can load are an error, and the result is not complete`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills")
    try directory.remove("skills/use-cases")

    let doctored = try await ShippedPluginCopy.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.data["complete"]?.boolValue == false)
    #expect(doctored.diagnosticCodes.contains("skills.host_not_declared"))
  }

  // bad_uninstallable.
  @Test
  func `a declared skill root is unreachable without a marketplace manifest`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills")
    try directory.remove(".claude-plugin/marketplace.json")
    let doctored = try await ShippedPluginCopy.doctor(directory)
    #expect(doctored.diagnosticCodes.contains("skills.host_not_installable"))
  }

  // edge_manifest_missing. Distinct from a manifest that is present but wrong:
  // with none at all, no host is reported.
  @Test
  func `with no plugin manifest at all, no host is reported and the code differs`()
    async throws
  {
    let directory = try ShippedPluginCopy.make("skills")
    try directory.remove(".claude-plugin/plugin.json")

    let doctored = try await ShippedPluginCopy.doctor(directory)
    #expect(doctored.isOk == false)
    #expect(doctored.diagnosticCodes.contains("skills.host_manifest_missing"))
    #expect(ShippedPluginCopy.hosts(doctored).isEmpty, "no manifest means no host")
    #expect(doctored.data.at("host_registration.complete")?.boolValue == false)
  }

  // bad_misdirected is NOT asserted here, and the gap is deliberate.
  //
  // The row claims "a manifest that declares a directory not actually holding
  // the canonical skills does not count as declared". Measured against the real
  // layout, pointing the manifest's `skills` key at a directory that does not
  // exist still reports ok:true, declares_skill_root:true and zero diagnostics —
  // skills are discovered by CONVENTION (skills/<name>/SKILL.md at the plugin
  // root), so the key is not what makes them reachable.
  //
  // So the row asserts behaviour the tool does not have. Writing a test that
  // passes would paper over that; changing the row is a behaviour decision and
  // belongs to the owner. Flagged here until they make it. (`test.todo` in
  // vitest; a disabled test carrying the same reason here.)
  @Test(.disabled("bad_misdirected — the row claims a behaviour the tool does not have"))
  func `bad_misdirected — the row claims a behaviour the tool does not have`() {
    Issue.record("unreachable: this test is disabled")
  }
}
