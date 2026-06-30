// The canonical skills the plugin ships. SINGLE SOURCE OF TRUTH: host projection
// (hosts/projectHostFiles), skill-asset validation (skills/validateSkillAssets),
// and the activation decision tree all read this one list — so a newly added
// skill can never be silently dropped from one surface. (The `migration` skill
// once was: host projection hard-coded a 3-item list that omitted it.)
export const CANONICAL_SKILLS = ["use-cases-plugin", "showcase", "walkthrough", "migration"] as const;

export type CanonicalSkill = (typeof CANONICAL_SKILLS)[number];
