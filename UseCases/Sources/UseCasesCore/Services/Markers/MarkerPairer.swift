struct MarkerPairer: MarkerPairing {
  func pair(_ sentinels: [MarkerSentinel]) -> MarkerPairingOutcome {
    var state = PairingState()

    for sentinel in sentinels {
      switch sentinel.kind {
      case .start:
        open(
          sentinel,
          state: &state,
        )
      case .end:
        close(
          sentinel,
          state: &state,
        )
      }
    }

    state.problems.append(contentsOf: state.open.map(MarkerPairingProblem.neverClosed))

    return MarkerPairingOutcome(
      pairs: state.pairs,
      problems: state.problems,
    )
  }

  /// Opens a start. One for a marker that is already open is nested inside itself.
  private func open(
    _ start: MarkerSentinel,
    state: inout PairingState,
  ) {
    if state.openCounts[start.identifier, default: 0] > 0,
       let outer = state.open.last(where: { $0.identifier == start.identifier })
    {
      state.problems.append(.nestedInItself(start, outer: outer))
    }

    state.open.append(start)
    state.openCounts[start.identifier, default: 0] += 1
  }

  /// Closes the latest open start with the same id. Any start opened after it stays open, and
  /// the two cross.
  private func close(
    _ end: MarkerSentinel,
    state: inout PairingState,
  ) {
    guard state.openCounts[end.identifier, default: 0] > 0,
          let index = state.open.lastIndex(where: { $0.identifier == end.identifier })
    else {
      state.problems.append(.withoutStart(end))
      return
    }

    let start = state.open.remove(at: index)
    state.openCounts[start.identifier, default: 0] -= 1
    state.pairs.append(MarkerPair(start: start, end: end))

    if index < state.open.count {
      state.problems.append(
        .crossing(
          end: end,
          start: start,
          stillOpen: state.open[index],
        ),
      )
    }
  }
}
