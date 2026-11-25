extension SignOffCounts {
  /// How many of the changes each tier signs: the ones that are not untouched; one with no tier is
  /// counted apart.
  init(counting changes: [ResolvedChange]) {
    let signed = changes.filter { change in
      change.fit != .untouched
    }

    func count(_ tier: ValueTier) -> Int {
      signed.filter { $0.shown.valueTier == tier }.count
    }

    self.init(
      critical: count(.critical),
      core: count(.core),
      supporting: count(.supporting),
      untiered: signed.filter { $0.shown.valueTier == nil }.count,
    )
  }
}
