@testable import UseCasesCore

/// The workspace samples of `docs/schemas/engine/validate.py`, as JSON.
enum WorkspaceSamples {
  static let all: [AuthoredSchemaSample] = valid + invalid

  private static let workspace = JSONMembers([
    "schema_version": "1",
    "prefix": #""shop""#,
    "use_cases_dir": #""use-cases""#,
    "freshness": #"{"binding_identity":"content","normalization":{"ignore":["line-endings"]}}"#,
    "discovery": #"{"exclude":["Generated/**"]}"#,
  ])

  private static let valid: [AuthoredSchemaSample] = [
    .valid("workspace", .workspace, workspace.json),
    .valid(
      "workspace with the sign-off gate",
      .workspace,
      workspace.setting("sign_off", #""required""#).json,
    ),
  ]

  private static let invalid: [AuthoredSchemaSample] = [
    .invalid(
      "sign_off optional",
      .workspace,
      workspace.setting("sign_off", #""optional""#).json,
    ),
    .invalid("recipes", .workspace, workspace.setting("recipes", "{}").json),
    .invalid("defaults", .workspace, workspace.setting("defaults", "{}").json),
    .invalid("missing version", .workspace, workspace.removing("schema_version").json),
  ]
}
