extension VerifyRunner {
  /// With the run's lock held: runs each command, then finishes the run, or seals it as
  /// interrupted when a signal stops the commands (chapter 13 §7, §15).
  func running(
    _ opened: OpenedRun,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
    store: VerifyStore,
    finishing: any FinishPointing,
  ) async -> Result<VerifiedRun, VerifyError> {
    do throws(VerifyError) {
      let run = try reopened(
        opened.run,
        store: store,
      )
      let stamp = try stamp(
        of: run,
        store: store,
      )
      var ran: [IdentifierSegment: RanCommand] = [:]

      for validation in opened.selected {
        let execution: CommandExecution = await cancellation.isCancelled()
          ? .cancelled
          : try await executor.execute(
            validation,
            in: run,
          )

        guard case let .ran(command) = execution else {
          return try .success(
            finishing.interrupt(
              run,
              planned: opened.selected,
              ran: ran,
            ),
          )
        }

        ran[validation.identifier] = command
      }

      return try await .success(
        finishing.finish(
          run,
          stamp: stamp,
          in: resolved,
          ran: ran,
          reloading: reloading,
        ),
      )
    } catch {
      return .failure(error)
    }
  }

  /// The run as it is on disk, which has to be unsealed.
  private func reopened(
    _ run: OpenRun,
    store: VerifyStore,
  ) throws(VerifyError) -> OpenRun {
    do {
      return try store.writer.reopenRun(
        run.identifier,
        in: run.workspace,
      )
    } catch {
      guard case .sealed = error else {
        throw .storage(error.description)
      }

      throw .alreadySealed(run.identifier.text)
    }
  }

  /// The start stamp the finish point judges against, as the run's folder holds it.
  private func stamp(
    of run: OpenRun,
    store: VerifyStore,
  ) throws(VerifyError) -> StartStamp {
    switch try store.find(
      run.identifier.text,
      in: run.workspace,
    ) {
    case let .open(found):
      return found.stamp
    case let .damaged(damaged):
      throw .storage(damaged.message)
    case .sealed:
      throw .alreadySealed(run.identifier.text)
    case .missing, .openRecord:
      throw .noSuchRun(run.identifier.text)
    }
  }
}
