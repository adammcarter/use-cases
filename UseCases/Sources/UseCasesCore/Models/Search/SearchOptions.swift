/// A new search, as the command line spells it (chapter 16 §15). Nothing is checked yet: the
/// flags are text, so that a refusal is in this command's own words.
public struct SearchOptions: Equatable, Sendable {
  public let subject: SearchSubject

  /// An id prefix, `--under`.
  public let under: String?

  /// A group, `--group`.
  public let group: String?

  /// Value tiers, `--tier`, comma separated.
  public let tiers: String?

  /// States, `--state`, comma separated.
  public let states: String?

  /// Fields, `--in`, comma separated.
  public let fields: String?

  /// `--exact`.
  public let isExact: Bool

  /// `--full`.
  public let wantsFull: Bool

  /// `--page-size`.
  public let pageSize: String?

  /// A new search.
  public init(
    subject: SearchSubject,
    under: String? = nil,
    group: String? = nil,
    tiers: String? = nil,
    states: String? = nil,
    fields: String? = nil,
    isExact: Bool = false,
    wantsFull: Bool = false,
    pageSize: String? = nil,
  ) {
    self.subject = subject
    self.under = under
    self.group = group
    self.tiers = tiers
    self.states = states
    self.fields = fields
    self.isExact = isExact
    self.wantsFull = wantsFull
    self.pageSize = pageSize
  }
}
