@testable import UseCasesCore

extension StoreHistorySupersededTests {
  /// The table of run shapes the rule is held to.
  static let shapes: [Shape] = [
    Shape(
      name: "code back at an older state keeps the run that decides it now",
      runs: [.sample(1, [result(card, first)]), .sample(2, [result(card, second)])],
      superseded: [],
      now: [card: first],
    ),
    Shape(
      name: "a route of the same use case does not say another route again",
      runs: [
        .sample(1, [result(card, first)]),
        .sample(2, [result(card, first, route: other)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "a route taken out is said again only by its own route, never by another",
      runs: [
        .sample(1, [result(card, first)]),
        .sample(2, [result(card, first, route: other)]),
      ],
      superseded: [],
      routes: [other],
    ),
    Shape(
      name: "a route taken out is said again by its own later result",
      runs: [
        .sample(1, [result(card, first)]),
        .sample(2, [result(card, second)]),
        .sample(3, [result(card, first, route: other)]),
      ],
      superseded: [1],
      routes: [other],
    ),
    Shape(
      name: "code back at an older state keeps the run whose diagnostic explains it now",
      runs: [
        .sample(1, [], diagnostics: [reason(card, first)]),
        .sample(2, [], diagnostics: [reason(card, second)]),
      ],
      superseded: [],
      now: [card: first],
    ),
    Shape(
      name: "a result said again at the same fingerprint",
      runs: [.sample(1, [result(card, first)]), .sample(2, [result(card, first)])],
      superseded: [1],
    ),
    Shape(
      name: "a result said again at another fingerprint",
      runs: [.sample(1, [result(card, first)]), .sample(2, [result(card, second)])],
      superseded: [1],
    ),
    Shape(
      name: "a run that is the newest source of one route is kept",
      runs: [
        .sample(1, [result(card, first), result(wallet, first)]),
        .sample(2, [result(card, first)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "every run but the newest goes in a chain",
      runs: [
        .sample(3, [result(card, first)]),
        .sample(1, [result(card, first)]),
        .sample(2, [result(card, second)]),
      ],
      superseded: [1, 2],
    ),
    Shape(
      name: "an empty run with a later sealed run",
      runs: [.sample(1, []), .sample(2, [result(card, first)])],
      superseded: [1],
    ),
    Shape(
      name: "an empty run that is the newest is kept",
      runs: [.sample(1, [result(card, first)]), .sample(2, [])],
      superseded: [],
    ),
    Shape(
      name: "an empty run with the newest diagnostic is kept",
      runs: [
        .sample(1, [], diagnostics: [reason(card, first)]),
        .sample(2, [result(wallet, first)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "a superseded result beside the newest diagnostic is kept",
      runs: [
        .sample(1, [result(card, first)], diagnostics: [reason(wallet, first)]),
        .sample(2, [result(card, first)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "a diagnostic said again by a later diagnostic",
      runs: [
        .sample(1, [], diagnostics: [reason(card, first)]),
        .sample(2, [], diagnostics: [reason(card, first)]),
      ],
      superseded: [1],
    ),
    Shape(
      name: "a diagnostic said again by a later result",
      runs: [
        .sample(1, [], diagnostics: [reason(card, first)]),
        .sample(2, [result(card, second)]),
      ],
      superseded: [1],
    ),
    Shape(
      name: "a result is not said again by a later diagnostic alone",
      runs: [
        .sample(1, [result(card, first)]),
        .sample(2, [], diagnostics: [reason(card, second)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "a diagnostic that names no route explains nothing",
      runs: [
        .sample(
          1,
          [result(card, first)],
          diagnostics: [
            RunDiagnostic(
              problem: "a link warning",
              useCase: nil,
              route: nil,
              fingerprint: nil,
              files: [],
              links: [],
            ),
          ],
        ),
        .sample(2, [result(card, first)]),
      ],
      superseded: [1],
    ),
    Shape(
      name: "a run read through its envelope is kept",
      runs: [
        .sample(1, [result(card, first)], diagnostics: nil),
        .sample(2, [result(card, first)]),
      ],
      superseded: [],
    ),
    Shape(
      name: "a single run is kept",
      runs: [.sample(1, [result(card, first)])],
      superseded: [],
    ),
    Shape(
      name: "a single empty run is kept",
      runs: [.sample(1, [])],
      superseded: [],
    ),
  ]
}
