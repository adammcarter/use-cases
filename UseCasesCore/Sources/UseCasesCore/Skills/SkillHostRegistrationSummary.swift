/// Whether one host can load the skills, as distinct from whether the files
/// exist (`SkillHostRegistrationSummary`).
public struct SkillHostRegistrationSummary: Sendable, Equatable {
  public let host: String
  public let manifestPath: String
  /// The manifest names a directory that holds every canonical skill.
  public let declaresSkillRoot: Bool
  /// The marketplace offers the plugin, so the manifest is read at all.
  public let isInstallable: Bool

  public init(
    host: String,
    manifestPath: String,
    declaresSkillRoot: Bool,
    isInstallable: Bool,
  ) {
    self.host = host
    self.manifestPath = manifestPath
    self.declaresSkillRoot = declaresSkillRoot
    self.isInstallable = isInstallable
  }

  /// `{ host, manifest_path, declares_skill_root, installable }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("host", .string(host)),
      ("manifest_path", .string(manifestPath)),
      ("declares_skill_root", .bool(declaresSkillRoot)),
      ("installable", .bool(isInstallable)),
    ]))
  }
}
