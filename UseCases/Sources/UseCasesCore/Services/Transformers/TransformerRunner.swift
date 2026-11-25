import Foundation

/// Runs transformers as separate processes under the process supervisor, talking to them through
/// two files in a private folder (chapter 10 §10).
struct TransformerRunner: TransformerRunning {
  /// How much of what a failing transformer printed a message keeps.
  static let consoleTailLength = 300

  private let locator: any TransformerLocating
  private let scratchMaker: any TransformerScratchMaking
  private let supervisor: any ProcessSupervising
  private let jsonReader: any JSONReading
  private let jsonWriter: any StoreJSONWriting
  private let timeout: Duration

  /// - Parameter timeout: How long a transformer has to answer: 120 seconds in production
  ///   (chapter 10 §10); a test passes a short time.
  init(
    locator: any TransformerLocating,
    scratchMaker: any TransformerScratchMaking,
    supervisor: any ProcessSupervising,
    jsonReader: any JSONReading,
    jsonWriter: any StoreJSONWriting,
    timeout: Duration = ProcessTimeout.transformer,
  ) {
    self.locator = locator
    self.scratchMaker = scratchMaker
    self.supervisor = supervisor
    self.jsonReader = jsonReader
    self.jsonWriter = jsonWriter
    self.timeout = timeout
  }

  func run(
    _ reference: TransformerReference,
    job: TransformerJob,
    request: StoreJSONValue,
    in root: URL,
  ) async throws(TransformerError) -> AuthoredObject {
    let name = reference.name
    let command = try locator.command(
      for: reference,
      in: root,
    )
    let scratch = try makeScratch(for: name)

    defer {
      scratch.remove()
    }

    do {
      try scratch.writeRequest(jsonWriter.pretty(request))
    } catch {
      throw .scratchUnavailable(
        name: name,
        reason: describe(error),
      )
    }

    let ended = try await start(
      command + [job.rawValue, scratch.request.path, scratch.response.path],
      named: name,
      in: root,
    )

    try require(
      ended,
      named: name,
    )

    return try answer(
      in: scratch,
      named: name,
    )
  }

  private func makeScratch(for name: String) throws(TransformerError) -> TransformerScratch {
    do {
      return try scratchMaker.makeScratch()
    } catch {
      throw .scratchUnavailable(
        name: name,
        reason: describe(error),
      )
    }
  }

  private func start(
    _ arguments: [String],
    named name: String,
    in root: URL,
  ) async throws(TransformerError) -> ProcessRun {
    let request = ProcessRequest(
      arguments: arguments,
      workingDirectory: root,
      reportPath: nil,
      timeout: timeout,
    )

    do {
      return try await supervisor.run(request)
    } catch {
      switch error {
      case let .couldNotLaunch(reason):
        throw .couldNotLaunch(
          name: name,
          reason: reason,
        )
      case .captureUnavailable, .waitFailed:
        throw .couldNotLaunch(
          name: name,
          reason: error.description,
        )
      }
    }
  }

  /// A transformer that ended by itself with code 0 has answered; every other ending is an error.
  private func require(
    _ run: ProcessRun,
    named name: String,
  ) throws(TransformerError) {
    switch run.termination {
    case .exited(0):
      return
    case let .exited(code):
      throw .exited(
        name: name,
        code: code,
        console: run.console.tail(limit: Self.consoleTailLength),
      )
    case let .signaled(signal):
      throw .signaled(
        name: name,
        signal: signal,
      )
    case let .timedOut(duration):
      throw .timedOut(
        name: name,
        after: duration,
      )
    case .cancelled:
      throw .cancelled
    }
  }

  /// The response as a JSON object that says contract 1 (chapter 10 §10, §14).
  private func answer(
    in scratch: TransformerScratch,
    named name: String,
  ) throws(TransformerError) -> AuthoredObject {
    let bytes: [UInt8]?

    do {
      bytes = try scratch.readResponse()
    } catch {
      throw .scratchUnavailable(
        name: name,
        reason: describe(error),
      )
    }

    guard let bytes else {
      throw .malformedResponse(
        name: name,
        reason: "no response.json was written",
      )
    }

    guard bytes.isStrictUTF8 else {
      throw .malformedResponse(
        name: name,
        reason: "response.json is not UTF-8 text",
      )
    }

    let value: AuthoredValue

    do {
      value = try jsonReader.read(bytes.lossyUTF8Text)
    } catch {
      throw .malformedResponse(
        name: name,
        reason: "response.json is not JSON: \(error)",
      )
    }

    return try checkedObject(
      value,
      named: name,
    )
  }

  private func checkedObject(
    _ value: AuthoredValue,
    named name: String,
  ) throws(TransformerError) -> AuthoredObject {
    let object: AuthoredObject

    do {
      object = try AuthoredObject(
        value,
        at: "",
      )
    } catch {
      throw .malformedResponse(
        name: name,
        reason: "response.json is not a JSON object",
      )
    }

    guard object.contains("contract") else {
      throw .unsupportedContract(name: name)
    }

    let contract: Int

    do {
      contract = try object.requiredInteger("contract")
    } catch {
      throw .malformedResponse(
        name: name,
        reason: "\(error)",
      )
    }

    guard contract == 1 else {
      throw .unsupportedContract(name: name)
    }

    return object
  }

  private func describe(_ error: TransformerScratchError) -> String {
    switch error {
    case let .unavailable(reason):
      reason
    }
  }
}
