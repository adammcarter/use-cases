import Testing
@testable import UseCasesCore

struct ResultsRendererTests {
  private let fixture: LayoutFixture

  init() throws {
    fixture = try LayoutFixture()
  }

  /// A proposal that removes `app.removed.gone` and saves the two use cases as the workspace
  /// holds them now: it has been applied.
  private func appliedProposal(
    editing edit: (String) -> String = { shown in
      shown
    },
  ) throws -> String {
    let toggle = try edit(fixture.batch.asShown("app.dark.toggle"))
    let other = try fixture.batch.asShown("app.dark.other")

    return Self.proposal(
      #""title": "Dark mode, again", "remove": ["app.removed.gone"]"#,
      saving: [toggle, other],
    )
  }

  /// A proposal file of these keys, saving these use cases.
  private static func proposal(
    _ keys: String,
    saving saves: [String],
  ) -> String {
    let list = saves.joined(separator: ", ")

    return "{" + keys + ", \"save\": [" + list + "]}"
  }

  private func results(
    _ useCases: [UseCaseStatus],
    proposal: String? = nil,
    signOffRequired: Bool = false,
  ) throws -> ResultsLayout {
    try fixture.results(
      proposal ?? appliedProposal(),
      judging: StatusSamples.workspace(
        useCases,
        signOffRequired: signOffRequired,
      ),
    )
  }

  private func holding() -> [UseCaseStatus] {
    [StatusSamples.useCase("app.dark.toggle"), StatusSamples.useCase("app.dark.other")]
  }

  @Test
  func `each saved use case is its status and the routes that gate it, by their ids`() throws {
    let layout = try results([
      StatusSamples.useCase(
        "app.dark.toggle",
        .stale,
        routes: [
          StatusSamples.route("unit-tests", status: .verified),
          StatusSamples.route("staging", status: .stale),
          StatusSamples.route("extra", status: .failed, gates: false),
        ],
      ),
      StatusSamples.useCase("app.dark.other", .draft),
    ])

    #expect(layout.title == "Dark mode, again")
    #expect(layout.useCases.map(\.useCase) == ["app.dark.toggle", "app.dark.other"])
    #expect(layout.useCases.map(\.status) == [.stale, .draft])
    #expect(layout.useCases.first?.checks == [
      ResultCheck(label: "unit-tests", status: .verified),
      ResultCheck(label: "staging", status: .stale),
    ])
    #expect(layout.useCases.last?.checks.isEmpty == true)
    #expect(layout.removed == ["app.removed.gone"])
  }

  @Test
  func `the gate is the one status asks, and a gate that blocks is still an answer`() throws {
    let passing = try results([
      StatusSamples.useCase("app.dark.toggle"),
      StatusSamples.useCase("app.dark.other"),
    ])
    let blocked = try results([
      StatusSamples.useCase("app.dark.toggle", .failed),
      StatusSamples.useCase("app.dark.other"),
    ])
    let unapproved = try results(
      [
        StatusSamples.useCase("app.dark.toggle", tier: "critical", approval: .unapproved),
        StatusSamples.useCase("app.dark.other"),
      ],
      signOffRequired: true,
    )

    #expect(passing.gatePasses)
    #expect(!blocked.gatePasses)
    #expect(!unapproved.gatePasses)
  }

  @Test
  func `a saved use case the workspace does not have is not applied yet`() {
    #expect(throws: LayoutRenderingError.notApplied(identifier: "app.dark.other")) {
      try results([StatusSamples.useCase("app.dark.toggle")])
    }
  }

  @Test
  func `a removed use case the workspace still has is not applied yet`() {
    #expect(throws: LayoutRenderingError.notApplied(identifier: "app.removed.gone")) {
      try results([
        StatusSamples.useCase("app.dark.toggle"),
        StatusSamples.useCase("app.dark.other"),
        StatusSamples.useCase("app.removed.gone"),
      ])
    }
  }

  @Test
  func `a workspace that cannot be judged is told as it was`() throws {
    let loaded = try fixture.batch.loaded()
    let renderer = try ResultsRenderer(
      reader: fixture.reader(sending: appliedProposal()),
      resolver: ProposalChangeResolver(),
      judge: MockStatusJudging(failing: .storage(problems: ["damaged"])),
      fingerprinter: PromiseFingerprinter(),
    )

    #expect(throws: LayoutRenderingError.status(.storage(problems: ["damaged"]))) {
      try renderer.results(
        readingFrom: "-",
        in: loaded,
        links: LinkResolver().resolveLinks(in: loaded),
      )
    }
  }

  // MARK: - A proposal is applied when its promises are what the workspace holds

  @Test
  func `a change-only proposal is not drawn before it is applied`() throws {
    let unapplied = try appliedProposal { shown in
      shown.replacingOccurrences(of: "Readable at night.", with: "Readable at dusk.")
    }

    #expect(throws: LayoutRenderingError.notApplied(identifier: "app.dark.toggle")) {
      try results(holding(), proposal: unapplied)
    }
  }

  @Test
  func `the proposal is drawn once the workspace holds what it saves`() throws {
    let layout = try results(holding())

    #expect(layout.useCases.map(\.useCase) == ["app.dark.toggle", "app.dark.other"])
  }

  @Test
  func `a route edited after the apply is still drawn: how it is proven is not the promise`(
  ) throws {
    let edited = try appliedProposal { shown in
      shown.replacingOccurrences(of: "Check it.", with: "Check it again, carefully.")
    }

    #expect(try results(holding(), proposal: edited).useCases.count == 2)
  }

  @Test(arguments: [
    ("Dark mode", "Darker mode"),
    ("Readable at night.", "Readable at dusk."),
    ("on-state", "on-states"),
    ("\"core\"", "\"critical\""),
  ])
  func `a promise edited after the apply is not drawn: title, intent, scenario or tier`(
    held: String,
    edited: String,
  ) throws {
    let proposal = try appliedProposal { shown in
      shown.replacingOccurrences(of: held, with: edited)
    }

    #expect(throws: LayoutRenderingError.notApplied(identifier: "app.dark.toggle")) {
      try results(holding(), proposal: proposal)
    }
  }

  @Test
  func `the first use case that is not as the proposal leaves it is named`() throws {
    let proposal = try appliedProposal { shown in
      shown.replacingOccurrences(of: "Dark mode", with: "Darker mode")
    }

    #expect(throws: LayoutRenderingError.notApplied(identifier: "app.removed.gone")) {
      try results(
        holding() + [StatusSamples.useCase("app.removed.gone")],
        proposal: proposal,
      )
    }
  }

  @Test
  func `results run the pointer checks of the brief and the proposal`() throws {
    let toggle = try fixture.batch.asShown("app.dark.toggle")

    let untouched = Self.proposal(#""title": "T", "untouched": ["app.nope.x"]"#, saving: [toggle])

    #expect(throws: LayoutRenderingError.unknownUseCase(identifier: "app.nope.x")) {
      try results(holding(), proposal: untouched)
    }
    #expect(throws: (any Error).self) {
      try results(
        holding(),
        proposal: Self.proposal(#""title": "T", "you_see": {"app.nope.x": "y"}"#, saving: [toggle]),
      )
    }
    #expect(throws: (any Error).self) {
      try results(
        holding(),
        proposal: Self.proposal(
          #""title": "T", "golden": {"app.dark.toggle": ["nope"]}"#,
          saving: [toggle],
        ),
      )
    }
    #expect(throws: (any Error).self) {
      try results(
        holding(),
        proposal: Self.proposal(
          #""title": "T", "fits": {"app.dark.other": "extends"}"#,
          saving: [toggle],
        ),
      )
    }
  }
}
