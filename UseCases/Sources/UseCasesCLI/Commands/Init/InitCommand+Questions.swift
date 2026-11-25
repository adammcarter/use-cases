import Foundation
import UseCasesCore

extension InitCommand {
  /// Asks what the flags did not say, and plans again with the answers. An existing workspace
  /// is asked only about hooks: its kind and prefix are already set. Hooks are asked about only
  /// inside a git repository.
  ///
  /// - Returns: The refusal that stopped the questions, or `nil` when they were all answered.
  func ask(
    session: InitSession,
    folder: URL,
    setup: inout InitSetup,
    plan: inout InitPlan,
    hooks: inout InitHooks,
  ) async -> CommandResult? {
    let asksAboutHooks = setup.hooks == nil

    do {
      try await interview(
        session: session,
        folder: folder,
        setup: &setup,
        plan: plan,
      )
    } catch {
      return refusal(
        .usage,
        "input ended before every question was answered; give the answers as "
          + "--minimal, --prefix and --hooks, or use --no-input",
      )
    }

    do {
      plan = try session.initializer.plan(setup.request(in: folder))
    } catch {
      return refusal(error)
    }

    guard asksAboutHooks, let answered = setup.hooks else {
      return nil
    }

    do {
      hooks = try await InitHooks.adding(
        answered,
        at: plan.root,
        using: session.hooks,
        program: session.program,
      )
    } catch {
      return refusal(
        .refused,
        error.message,
      )
    }

    return nil
  }

  /// The questions the flags left, in order, and the answers set on `setup`.
  private func interview(
    session: InitSession,
    folder: URL,
    setup: inout InitSetup,
    plan: InitPlan,
  ) async throws(InitInterviewError) {
    let interview = InitInterview(prompter: session.prompter)

    if !plan.isExistingWorkspace {
      if !minimal {
        setup.form = try await interview.form()
      }

      if prefix == nil {
        let form = setup.form

        setup.prefix = try await interview.prefix { text in
          prefixProblem(
            text,
            form: form,
            folder: folder,
            initializer: session.initializer,
          )
        }
      }
    }

    if setup.hooks == nil,
       await InitHooks.isInGitRepository(
         plan.root,
         using: session.hooks,
       )
    {
      setup.hooks = try await interview.hooks()
    }
  }

  /// What is wrong with a prefix the person typed, in the words of the refusal.
  private func prefixProblem(
    _ text: String,
    form: InitForm,
    folder: URL,
    initializer: any WorkspaceInitializing,
  ) -> String? {
    do {
      _ = try initializer.plan(
        InitRequest(
          folder: folder,
          form: form,
          prefix: text,
        ),
      )

      return nil
    } catch {
      guard case .invalidPrefix = error else {
        return nil
      }

      return error.message
    }
  }
}
