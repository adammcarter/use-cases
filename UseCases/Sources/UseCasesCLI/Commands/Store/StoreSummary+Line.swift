import UseCasesCore

extension StoreSummary {
  /// The store's line under `status` (chapter 16 §9): `results: 12 runs · 450 MB`, and how many
  /// runs `prune` would remove when it would remove any.
  var line: String {
    var parts = [
      "results: " + (runs == 1 ? "1 run" : "\(runs) runs"),
      ByteText.text(bytes),
    ]

    if superseded > 0 {
      parts.append("\(superseded) superseded")
    }

    return parts.joined(separator: " · ")
  }
}
