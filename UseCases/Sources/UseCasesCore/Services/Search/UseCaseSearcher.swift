/// Matches the words of a search to the fields of every use case, and ranks what matches.
public struct UseCaseSearcher: UseCaseSearching {
  private let targeter: any UseCaseTargeting
  private let groupSelector: any GroupSelecting
  private let matcher: any TextMatching
  private let digester: any SearchDigesting
  private let codec: any SearchTokenCoding

  /// Makes the searcher.
  public init() {
    self.init(
      targeter: UseCaseTargeter(),
      groupSelector: GroupSelector(),
      matcher: TextMatcher(),
      digester: SearchDigester(),
      codec: SearchTokenCodec(),
    )
  }

  init(
    targeter: any UseCaseTargeting,
    groupSelector: any GroupSelecting,
    matcher: any TextMatching,
    digester: any SearchDigesting,
    codec: any SearchTokenCoding,
  ) {
    self.targeter = targeter
    self.groupSelector = groupSelector
    self.matcher = matcher
    self.digester = digester
    self.codec = codec
  }

  public func search(
    _ plan: SearchPlan,
    in workspace: LoadedWorkspace,
    status: WorkspaceStatus,
  ) throws(UseCaseSearchError) -> SearchPage {
    let members = try members(
      of: plan,
      in: workspace,
    )
    let state = digester.digest(
      of: workspace,
      status: status,
      groupMembers: members.map(Self.sorted),
    )

    if let seal = plan.seal,
       seal != digester.seal(
         of: plan.parameters,
         state: state,
       )
    {
      throw .changed
    }

    let kept = try candidates(
      of: plan,
      in: workspace,
      status: status,
      members: members,
    )
    let ranked = rank(
      kept,
      by: plan,
    )
    let window = PageWindow(
      total: ranked.count,
      offset: plan.offset,
      size: plan.pageSize,
    )

    return SearchPage(
      total: window.total,
      offset: window.offset,
      pageSize: window.size,
      matches: ranked[window.range].map { ranked in
        match(
          ranked,
          plan: plan,
        )
      },
      next: window.nextOffset.map { offset in
        token(
          moving: plan,
          to: offset,
          state: state,
        )
      },
    )
  }

  /// The members of the group the search is limited to. A group a later page names that is gone
  /// is not told here: the digest has changed, and the page is refused as changed.
  private func members(
    of plan: SearchPlan,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseSearchError) -> Set<String>? {
    guard let group = plan.filters.group else {
      return nil
    }

    do {
      return try groupSelector.members(
        ofGroup: group,
        in: workspace,
      )
    } catch {
      guard plan.seal == nil else {
        return nil
      }

      throw .group(error)
    }
  }

  private static func sorted(_ members: Set<String>) -> [String] {
    members.sorted { lhs, rhs in
      lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
  }

  /// The use cases the filters keep, with their status.
  private func candidates(
    of plan: SearchPlan,
    in workspace: LoadedWorkspace,
    status: WorkspaceStatus,
    members: Set<String>?,
  ) throws(UseCaseSearchError) -> [Candidate] {
    var named: Set<String>?

    if let under = plan.filters.under {
      do {
        named = try targeter.identifiers(
          matching: under,
          in: workspace,
        )
      } catch {
        throw .target(error)
      }
    }

    let statuses = Dictionary(
      status.useCases.map { useCase in
        (useCase.identifier, useCase)
      },
      uniquingKeysWith: { first, _ in
        first
      },
    )

    return workspace.useCases.compactMap { useCase in
      let identifier = useCase.identifier.text

      guard
        let judged = statuses[identifier],
        named?.contains(identifier) ?? true,
        members?.contains(identifier) ?? true,
        plan.filters.states.isEmpty || plan.filters.states.contains(judged.status),
        Self.isKept(
          useCase.definition.valueTier,
          among: plan.filters.tiers,
        ),
        !identifier.isExactlyEqual(to: plan.filters.excluded ?? "")
      else {
        return nil
      }

      return Candidate(
        useCase: useCase,
        status: judged.status,
      )
    }
  }

  private static func isKept(
    _ tier: ValueTier?,
    among tiers: Set<ValueTier>,
  ) -> Bool {
    guard !tiers.isEmpty else {
      return true
    }

    return tier.map(tiers.contains) ?? false
  }

  /// The use cases that match, best first, ties by the bytes of the id.
  private func rank(
    _ candidates: [Candidate],
    by plan: SearchPlan,
  ) -> [Ranked] {
    let fields = Set(plan.fields)
    var ranked: [Ranked] = []

    for candidate in candidates {
      let passages = candidate.useCase.passages(in: fields)
      let found = matcher.match(
        plan.query,
        in: passages.map(\.passage),
      )

      if let found {
        ranked.append(
          Ranked(
            candidate: candidate,
            passages: passages,
            match: found,
          ),
        )
      }
    }

    return ranked.sorted { lhs, rhs in
      guard lhs.match.score == rhs.match.score else {
        return lhs.match.score > rhs.match.score
      }

      return lhs.candidate.useCase.identifier.text.utf8.lexicographicallyPrecedes(
        rhs.candidate.useCase.identifier.text.utf8,
      )
    }
  }

  private func match(
    _ ranked: Ranked,
    plan: SearchPlan,
  ) -> SearchMatch {
    let useCase = ranked.candidate.useCase

    return SearchMatch(
      identifier: useCase.identifier.text,
      title: useCase.definition.title,
      file: useCase.file.text,
      status: ranked.candidate.status,
      valueTier: useCase.definition.valueTier?.rawValue,
      score: Double(ranked.match.score) / Double(TextMatch.bestScore),
      reasons: ranked.match.hits.map { hit in
        let place = ranked.passages[hit.index]

        return SearchReason(
          field: place.field,
          location: place.location,
          text: place.passage.text,
        )
      },
      definition: plan.wantsFull
        ? useCase.definition.document(identifier: useCase.identifier)
        : nil,
    )
  }

  private func token(
    moving plan: SearchPlan,
    to offset: Int,
    state: String,
  ) -> String {
    let next = plan.moved(to: offset)

    return codec.token(
      for: next.document(
        sealedBy: digester.seal(
          of: next.parameters,
          state: state,
        ),
      ),
    )
  }

  private struct Candidate {
    let useCase: LoadedUseCase
    let status: VerificationStatus
  }

  private struct Ranked {
    let candidate: Candidate
    let passages: [UseCasePassage]
    let match: TextMatch
  }
}
