/// A claim no skill text may make (`FORBIDDEN_PATTERNS`).
///
/// Each pattern is a case-insensitive run of words separated by whitespace,
/// so it is held as its phrasings: each phrasing a list of word groups, any
/// word of a group matching there, the groups joined by one or more
/// whitespace characters. Words are lowercase; the literal spaces inside a
/// word are the pattern's own single spaces.
struct SkillForbiddenClaim: Sendable {
  let code: String
  let message: String
  let phrasings: [[[String]]]
  /// The pattern opens with `\b`.
  let isWordBounded: Bool

  static let all: [SkillForbiddenClaim] = [
    SkillForbiddenClaim(
      code: "skills.mandatory_showcase_claim",
      message: "Skill text must not make showcase mandatory for all work.",
      phrasings: [
        [["showcase"], ["is"], ["mandatory"]],
        [["required"], ["showcase"], ["for"], ["all"], ["work"]],
      ],
      isWordBounded: false,
    ),
    SkillForbiddenClaim(
      code: "skills.generated_material_claim",
      message: "Generated material must not be described as proof.",
      phrasings: [[
        ["generated"],
        ["plan", "walkthrough", "capsule", "runbook"],
        ["is"],
        ["proof"],
      ]],
      isWordBounded: false,
    ),
    SkillForbiddenClaim(
      code: "skills.agent_user_approval_claim",
      message: "Agents must not be permitted to claim user approval.",
      phrasings: [[
        ["agent", "agents"],
        ["may"],
        ["claim", "record"],
        ["user approval", "user sign-off"],
      ]],
      isWordBounded: false,
    ),
    SkillForbiddenClaim(
      code: "skills.host_support_claim",
      message: "Host support must not be claimed without evidence.",
      phrasings: [[["host"], ["support"], ["is"], ["verified."]]],
      isWordBounded: true,
    ),
  ]
}
