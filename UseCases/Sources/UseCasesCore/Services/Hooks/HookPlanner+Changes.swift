import Foundation

extension HookPlanner {
  /// What the planner has settled so far, hook by hook.
  struct Outcome {
    var hooks: [HookStatus] = []
    var changed: [HookName] = []
    var changes: [FileChange] = []
    var notes: [String] = []
    var needsAttention = false
  }

  /// What the hook is in this clone.
  func state(
    of script: HookScript,
    in location: GitLocation,
  ) throws(HooksError) -> HookState {
    guard !location.isManaged else {
      return .managed
    }

    let file = location.hooksFolder.appendingPathComponent(script.hook.event)

    do {
      switch try fileSystem.kindOfItem(at: file) {
      case nil:
        return .absent
      case .file?:
        let bytes = try fileSystem.readBytes(at: file)

        // Bytes that are not text are not the script.
        guard let text = String(bytes: bytes, encoding: .utf8) else {
          return .other
        }

        return script.isOurs(text) ? .installed : .other
      case .directory?, .symlink?, .other?:
        return .other
      }
    } catch {
      throw .unreadable(
        path: file.path,
        reason: error.description,
      )
    }
  }

  /// Settles one hook: written, removed, or left alone with the line the person needs.
  func change(
    _ script: HookScript,
    state: HookState,
    request: HooksRequest,
    location: GitLocation,
    outcome: inout Outcome,
  ) throws(HooksError) {
    let hook = script.hook
    var after = state

    if let action = request.action, request.names.contains(hook) {
      switch (action, state) {
      case (.add, .absent):
        let file = try path(
          of: hook,
          in: location,
        )

        outcome.changes.append(
          .create(
            file,
            text: script.text(program: request.program),
            isExecutable: true,
          ),
        )
        outcome.changed.append(hook)
        after = .installed
      case (.remove, .installed):
        let file = try path(
          of: hook,
          in: location,
        )

        outcome.changes.append(.delete(file))
        outcome.changed.append(hook)
        after = .absent
      case (_, .managed), (_, .other):
        outcome.notes.append(
          Self.note(
            for: action,
            state: state,
            script: script,
          ),
        )
        outcome.needsAttention = true
      case (.add, .installed), (.remove, .absent):
        break
      }
    }

    outcome.hooks.append(
      HookStatus(
        name: hook,
        state: after,
      ),
    )
  }

  /// The hook's file, below the folder above the hooks folder, where the plan is applied.
  private func path(
    of hook: HookName,
    in location: GitLocation,
  ) throws(HooksError) -> WorkspacePath {
    do {
      return try WorkspacePath.root
        .appending(component: location.hooksFolder.lastPathComponent)
        .appending(component: hook.event)
    } catch {
      throw .unreadable(
        path: location.hooksFolder.path,
        reason: "its name cannot be written as a path",
      )
    }
  }

  /// What is told when a hook is left alone (chapter 18 §4).
  private static func note(
    for action: HookAction,
    state: HookState,
    script: HookScript,
  ) -> String {
    let event = script.hook.event

    switch (action, state) {
    case (.add, .managed):
      return "a hook manager owns this clone's hooks (core.hooksPath), so nothing was written; "
        + "add this to its \(event) hook: \(script.line)"
    case (.remove, .managed):
      return "a hook manager owns this clone's hooks (core.hooksPath), so nothing was removed; "
        + "remove the use-cases line from its \(event) hook yourself"
    case (.add, _):
      return "\(event) already has a hook that Use Cases did not write; it is left alone. "
        + "To add the check, add this line to it: \(script.line)"
    case (.remove, _):
      return "\(event) is not the hook Use Cases wrote; it is left alone. "
        + "Remove the use-cases line from it yourself if it has one."
    }
  }
}
