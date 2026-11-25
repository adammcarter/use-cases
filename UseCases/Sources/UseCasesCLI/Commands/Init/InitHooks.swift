import Foundation
import UseCasesCore

/// What `init` does about hooks: the plan to add them, and what is told when it cannot.
struct InitHooks {
  /// No hooks asked for.
  static let none = InitHooks(
    plan: nil,
    notes: [],
    needsAttention: false,
  )

  /// The plan; `nil` when there is no clone to add them to.
  let plan: HooksPlan?
  let notes: [String]

  /// A hook was left alone or could not be added: `init` is done, and something needs the
  /// person (chapter 17 §8).
  let needsAttention: Bool

  /// The hooks this request adds.
  var added: [HookName] {
    plan?.changed ?? []
  }

  /// The hooks to write beside the workspace.
  var writes: [FolderWrite] {
    plan.map { [$0.writes] } ?? []
  }

  /// Plans adding `names` to the clone `root` is in; none, when no hook was asked for. A folder
  /// that is not in a git repository is not a refusal: the files are still made, and the person
  /// is told no hook was added.
  static func adding(
    _ names: [HookName]?,
    at root: URL,
    using planner: any HookPlanning,
    program: String,
  ) async throws(HooksError) -> InitHooks {
    guard let names, !names.isEmpty else {
      return .none
    }

    do throws(HooksError) {
      let plan = try await planner.plan(
        HooksRequest(
          root: root,
          action: .add,
          names: names,
          program: program,
        ),
      )

      return InitHooks(
        plan: plan,
        notes: plan.notes,
        needsAttention: plan.needsAttention,
      )
    } catch {
      guard case .notAGitRepository = error else {
        throw error
      }

      return InitHooks(
        plan: nil,
        notes: ["not a git repository, so no hooks were added"],
        needsAttention: true,
      )
    }
  }

  /// Whether `root` is in a git repository, which decides whether hooks are asked about.
  static func isInGitRepository(
    _ root: URL,
    using planner: any HookPlanning,
  ) async -> Bool {
    let listing = HooksRequest(
      root: root,
      action: nil,
      names: [],
      program: "",
    )

    return await (try? planner.plan(listing)) != nil
  }
}
