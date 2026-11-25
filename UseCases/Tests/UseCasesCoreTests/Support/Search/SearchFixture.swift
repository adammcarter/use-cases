import Foundation
@testable import UseCasesCore

/// The feed of the acceptance suite's `search` tests on disk: four use cases, one of them a
/// draft, and a group, searched by the real planner and searcher.
struct SearchFixture {
  let workspace: WorkspaceFixture

  init() throws {
    workspace = try WorkspaceFixture()
    try workspace.write(
      "use-cases/feed/post.yml",
      "prefix: feed.post\nuse_cases:\n"
        + Self.useCase(
          "like",
          "Double tap to like a post",
          when: "The user taps a post twice",
          tier: "critical",
        )
        + Self.useCase(
          "unlike",
          "Undo a like",
          when: "The user double-taps a liked post again",
        ),
    )
    try workspace.write(
      "use-cases/feed/media.yml",
      "prefix: feed.media\nuse_cases:\n"
        + Self.useCase(
          "zoom",
          "Zoom a photo",
          when: "The user pinches a photo",
          outOfScope: "Double tap to zoom",
        ),
    )
    try workspace.write(
      "use-cases/settings.yml",
      "prefix: settings\nuse_cases:\n"
        + Self.useCase(
          "theme",
          "Switch to a dark theme",
          tier: "supporting",
          isReady: false,
        ),
    )
    try workspace.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  social:\n    include: { prefixes: [app.feed.post] }\n",
    )
  }

  /// The identifiers a search finds, best first.
  func found(
    _ subject: SearchSubject,
    under: String? = nil,
    group: String? = nil,
    tiers: String? = nil,
    states: String? = nil,
    fields: String? = nil,
    isExact: Bool = false,
  ) throws -> [String] {
    try page(
      subject,
      under: under,
      group: group,
      tiers: tiers,
      states: states,
      fields: fields,
      isExact: isExact,
    ).matches.map(\.identifier)
  }

  /// One page of a new search.
  func page(
    _ subject: SearchSubject,
    under: String? = nil,
    group: String? = nil,
    tiers: String? = nil,
    states: String? = nil,
    fields: String? = nil,
    isExact: Bool = false,
    wantsFull: Bool = false,
    pageSize: String? = nil,
  ) throws -> SearchPage {
    try page(
      of: .new(
        SearchOptions(
          subject: subject,
          under: under,
          group: group,
          tiers: tiers,
          states: states,
          fields: fields,
          isExact: isExact,
          wantsFull: wantsFull,
          pageSize: pageSize,
        ),
      ),
    )
  }

  /// One page of whatever the request asks, against the workspace as it is on disk now.
  func page(of request: SearchRequest) throws -> SearchPage {
    let loaded = try workspace.loaded()
    let status = try StatusJudge().judge(
      loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )

    return try UseCaseSearcher().search(
      SearchPlanner(workingDirectory: workspace.directory.url).plan(request),
      in: loaded,
      status: status,
    )
  }

  /// Records a verdict for the manual route of a use case, as `record` does.
  func record(
    _ useCase: String,
    _ status: String = "pass",
  ) throws {
    let clock = FixedTimekeeper()
    let recorder = VerdictRecorder(
      fingerprinter: RouteFingerprintComputer(),
      writing: Result { () throws(StoreSchemaLoadingError) in
        try RunWriter(
          clock: clock,
          random: FixedRandomBits(),
        )
      },
      reader: LocalAttachmentReader(),
      clock: clock,
    )
    let loaded = try workspace.loaded()

    _ = try recorder.commit(
      recorder.plan(
        RecordRequest(
          useCase: useCase,
          route: "manual",
          status: status,
          message: nil,
          attachments: [],
        ),
        in: loaded,
        links: LinkResolver().resolveLinks(in: loaded),
      ),
    )
  }

  private static func useCase(
    _ local: String,
    _ title: String,
    when: String = "",
    tier: String = "core",
    outOfScope: String? = nil,
    isReady: Bool = true,
  ) -> String {
    var text = "  - id: \(local)\n    title: \(title)\n    value_tier: \(tier)\n"

    if isReady {
      text += "    intent: \(title).\n    scenarios:\n      - id: main\n"
        + "        when: [\(when)]\n        then: [It works.]\n"
        + "    validation:\n      - id: manual\n        type: { kind: acceptance }\n"
        + "        covers: [main]\n        procedure:\n          steps: [Check it.]\n"
    }

    if let outOfScope {
      text += "    out_of_scope: [\(outOfScope)]\n"
    }

    return text
  }
}
