/// The canonical preset ids (verifierPresets.ts `VERIFIER_PRESET_IDS`), in the
/// TypeScript's order. Kept in sync with the `verifier_preset_id` enum in
/// schemas/v1/common.schema.json.
public enum VerifierPresetIdentifier: String, CaseIterable, Equatable, Sendable {
  case commandGeneric = "command.generic"
  case javaScriptVitest = "js.vitest"
  case javaScriptNpmTest = "js.npm-test"
  case pythonPytest = "python.pytest"
  case goTest = "go.test"
  case makeTarget = "make.target"

  /// The preset whose id is exactly `value`, compared by code unit.
  public init?(identifier value: String) {
    guard let match = Self.allCases.first(where: { candidate in
      JavaScriptString.identical(candidate.rawValue, value)
    }) else {
      return nil
    }
    self = match
  }
}

/// A preset expanded for one slug: always a script.
public struct ExpandedPreset: Equatable, Sendable {
  public let command: [String]
  public let inputs: [String]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("kind", .string("script")),
      ("command", .array(command.map(JSONValue.string))),
      ("inputs", .array(inputs.map(JSONValue.string))),
    ]))
  }
}

/// A resolved expansion, or BLOCKED for an unknown preset id (never thrown).
public enum PresetExpansion: Equatable, Sendable {
  case resolved(preset: VerifierPresetIdentifier, expansion: ExpandedPreset)
  case blocked(reason: String)

  var jsonValue: JSONValue {
    switch self {
    case let .resolved(preset, expansion):
      .object(JSONObject([
        ("status", .string("resolved")),
        ("preset", .string(preset.rawValue)),
        ("expansion", expansion.jsonValue),
      ]))
    case let .blocked(reason):
      .object(JSONObject([
        ("status", .string("blocked")),
        ("reason", .string(reason)),
      ]))
    }
  }
}

/// Language-agnostic verifier presets (verifierPresets.ts): a named, reusable
/// answer to "what command verifies this row", expanded with `{slug}` (and, for
/// a variant row, `{variant}`) substituted everywhere it appears.
public enum VerifierPresets {
  //: @use-case:lifecycle.signals.run_class_is_derived
  /// Is this preset, by definition, a TEST SUITE — a runner invoked over a test
  /// file or package? `make.target` and `command.generic` are not: they may
  /// genuinely drive the shipped product, and the tool cannot tell.
  public static func isTestSuitePreset(_ preset: String?) -> Bool {
    guard let preset, let identifier = VerifierPresetIdentifier(identifier: preset) else {
      return false
    }
    return testSuitePresets.contains(identifier)
  }

  //: @use-case:end lifecycle.signals.run_class_is_derived

  /// Expand `presetIdentifier` for `slug`; an unknown id is BLOCKED.
  public static func expand(
    presetIdentifier: String,
    slug: String,
    variant: String?,
  ) -> PresetExpansion {
    guard let preset = VerifierPresetIdentifier(identifier: presetIdentifier) else {
      let known = VerifierPresetIdentifier.allCases.map(\.rawValue).joined(separator: ", ")
      return .blocked(
        reason: "unknown verifier preset '\(presetIdentifier)'; known presets: \(known)",
      )
    }
    let template = template(for: preset)
    return .resolved(preset: preset, expansion: ExpandedPreset(
      command: template.command.map { part in
        substituteTokens(part, slug: slug, variant: variant)
      },
      inputs: template.inputs.map { part in
        substituteTokens(part, slug: slug, variant: variant)
      },
    ))
  }

  /// `{slug}` replaced everywhere, then — only when there is a variant —
  /// `{variant}` everywhere, so a slug that itself spells `{variant}` is
  /// substituted too, exactly as the TypeScript's two passes do.
  static func substituteTokens(
    _ value: String,
    slug: String,
    variant: String?,
  ) -> String {
    let withSlug = replacingAll(value, token: slugToken, with: slug)
    guard let variant else {
      return withSlug
    }
    return replacingAll(withSlug, token: variantToken, with: variant)
  }

  /// `value.split(token).join(replacement)` for one of the two non-empty
  /// tokens: every non-overlapping occurrence, scanned left to right by code
  /// unit, replaced.
  private static func replacingAll(
    _ value: String,
    token: String,
    with replacement: String,
  ) -> String {
    let units = Array(value.utf16)
    let tokenUnits = Array(token.utf16)
    var result: [UInt16] = []
    var index = 0
    while index < units.count {
      if units[index...].starts(with: tokenUnits) {
        result += replacement.utf16
        index += tokenUnits.count
      } else {
        result.append(units[index])
        index += 1
      }
    }
    return CodeUnits.string(result)
  }

  private static let slugToken = "{slug}"
  private static let variantToken = "{variant}"

  private static let testSuitePresets: [VerifierPresetIdentifier] = [
    .javaScriptVitest,
    .javaScriptNpmTest,
    .pythonPytest,
    .goTest,
  ]

  /// The raw, un-substituted templates. `command.generic` ships an empty
  /// command on purpose: the caller supplies the argv.
  private static func template(for preset: VerifierPresetIdentifier)
    -> (command: [String], inputs: [String])
  {
    switch preset {
    case .commandGeneric:
      ([], [])
    case .javaScriptVitest:
      (
        ["npx", "--no-install", "vitest", "run", "tests/use-cases/{slug}.test.ts"],
        ["tests/use-cases/{slug}.test.ts"],
      )
    case .javaScriptNpmTest:
      (["npm", "test"], [])
    case .pythonPytest:
      (["pytest", "tests/use_cases/{slug}_test.py"], ["tests/use_cases/{slug}_test.py"])
    case .goTest:
      (["go", "test", "./..."], [])
    case .makeTarget:
      (["make", "test-use-case", "SLUG={slug}"], [])
    }
  }
}
