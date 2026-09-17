/// The commands a skill or agent body may tell its reader to run
/// (packages/core/src/cli/knownCommands.ts). They mirror the CLI's command
/// registry; row 4's CLI must keep them in step with the commands it really
/// has.
public enum KnownCliCommands {
  /// `KNOWN_CLI_COMMANDS`: two-token commands, `"<command> <subcommand>"`.
  public static let twoToken: [String] = [
    "capsule list",
    "capsule plan",
    "capsule run",
    "capsule validate",
    "doctor roots",
    "doctor skills",
    "evidence record",
    "evidence status",
    "evidence void",
    "matrix list",
    "matrix remove",
    "matrix status",
    "matrix upsert",
    "matrix validate",
    "plan cards",
    "plan showcase",
    "plan walkthrough",
    "schema list",
    "schema validate-fixtures",
    "showcase approve",
    "showcase correct",
    "showcase decide",
    "showcase finish",
    "showcase pause",
    "showcase record-observation",
    "showcase record-verdict",
    "showcase reject",
    "showcase request-approval",
    "showcase resume",
    "showcase start",
    "showcase status",
    "workflow mode",
    "workflow set-mode",
  ]

  /// `BUILTIN_FLAT_CLI_COMMANDS`: handled outside the registry, still real.
  public static let builtinFlat: [String] = ["init", "version"]

  /// `KNOWN_FLAT_CLI_COMMANDS`: single-segment commands, validated by their
  /// bare name because a flag may follow them.
  public static let flat: [String] = [
    "approve-run",
    "bind",
    "impact",
    "init",
    "keygen",
    "prove",
    "rebind",
    "recover",
    "scan",
    "unbind",
    "validate-ledger",
    "verify",
    "version",
  ]

  /// A reference's command is a known pair, or its first whitespace-separated
  /// token a known bare command. Compared by code unit, as `Set.has` compares.
  public static func isKnown(_ command: String) -> Bool {
    let bare = SkillText.splitOnWhitespace(command).first ?? ""
    let isKnownPair = twoToken.contains { known in
      JavaScriptString.identical(known, command)
    }
    return isKnownPair || flat.contains { known in
      JavaScriptString.identical(known, bare)
    }
  }
}
