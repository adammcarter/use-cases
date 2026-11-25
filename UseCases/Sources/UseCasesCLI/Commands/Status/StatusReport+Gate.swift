import UseCasesCore

extension StatusReport {
  /// The gate's answer for people (chapter 16 §10): the use cases that block or warn, as `status`
  /// lists them, then one line that counts them, then the warnings.
  func gateText(
    _ gate: Gate,
    hint: Bool,
  ) -> String {
    var marks: [String: String] = [:]

    for (entries, blocks) in [(gate.blocking, true), (gate.warning, false)] {
      for entry in entries {
        marks[entry.useCase] = Self.mark(
          of: entry,
          blocks: blocks,
        )
      }
    }

    let held = Set(gate.blocking.map(\.useCase) + gate.warning.map(\.useCase))
    let listed = shown.filter { useCase in
      held.contains(useCase.identifier)
    }

    var lines = listing(
      of: listed,
      marks: marks,
    )

    if !lines.isEmpty {
      lines.append("")
    }

    lines.append(Self.gateLine(gate))

    // What is worth saying about the workspace is never hidden from the gate (chapter 16 §9).
    lines += warningLines()

    if hint, let first = gate.blocking.first {
      lines.append(hintLine("status \(first.useCase)"))
    }

    return lines.joined(separator: "\n")
  }

  /// `gate: blocked · 2 block (1 stale, 1 not approved) · 1 warning (1 unverified)`.
  static func gateLine(_ gate: Gate) -> String {
    let name = gate.isStrict ? "gate (strict)" : "gate"
    var parts = [gate.passed ? "\(name): clear" : "\(name): blocked"]

    if !gate.blocking.isEmpty {
      parts.append("\(gate.blocking.count) block (\(reasons(of: gate.blocking)))")
    }

    if !gate.warning.isEmpty {
      parts.append("\(count(gate.warning.count, "warning")) (\(reasons(of: gate.warning)))")
    }

    return parts.joined(separator: " · ")
  }

  /// What the gate adds to a use case's line: nothing where its state blocks, `(not approved)`
  /// where its sign-off does, and `(warning)` or `(warning: not approved)` where it only warns.
  /// A promise that changed after its sign-off is already said on the line as `changed since
  /// approved`, so it is not said again.
  private static func mark(
    of entry: GateEntry,
    blocks: Bool,
  ) -> String? {
    let note = entry.heldForApproval == .unapproved ? "not approved" : nil

    guard blocks else {
      return (["warning"] + [note].compactMap(\.self)).joined(separator: ": ").parenthesized
    }

    guard entry.reason == .notApproved else {
      return nil
    }

    return note?.parenthesized
  }

  /// `1 stale, 1 not approved`: how many entries have each reason, the states worst first and
  /// sign-off last.
  private static func reasons(of entries: [GateEntry]) -> String {
    var counts: [String] = []

    for status in VerificationStatus.allCases {
      let number = entries.count { entry in
        entry.reason == .status(status)
      }

      if number > 0 {
        counts.append("\(number) \(status.rawValue)")
      }
    }

    let unapproved = entries.count { entry in
      entry.reason == .notApproved
    }

    if unapproved > 0 {
      counts.append("\(unapproved) not approved")
    }

    return counts.joined(separator: ", ")
  }
}
