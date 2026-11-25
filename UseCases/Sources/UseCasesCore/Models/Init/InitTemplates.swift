/// The text of the files `init` writes (chapter 17 §4 to §7): every one is valid, and none holds a
/// test command or anything else specific to the codebase.
enum InitTemplates {
  /// The root `use-cases.yml`: the prefix when one is asked for, otherwise the option as a
  /// comment; then the discovery exclusions as a comment, for the person to fill in.
  static func workspace(prefix: Namespace?) -> String {
    guard let prefix else {
      return """
      schema_version: 1
      root: true
      # prefix: shop    # optional: a namespace at the front of every use case id.
      #                 # Choose it once: changing it later renames every use case.
      \(exclusions)

      """
    }

    return """
    schema_version: 1
    root: true
    prefix: \(prefix.text)
    \(exclusions)

    """
  }

  /// The discovery exclusions as a comment (chapter 04): folders never searched for use cases or
  /// markers. Only an example: the folders are the codebase's, and init never names them.
  static let exclusions = """

  # discovery:        # optional: folders never searched for use cases or markers,
  #   exclude:        # such as build output, or test data that holds marker text as data.
  #     - "build/**"
  #     - "tests/fixtures/**"
  """

  /// A worked use case, left a DRAFT on purpose: its value tier is a comment. It ends inside the
  /// use case, so that the next one is added after it.
  static let example = """
  # A worked example of a use case: fill it in, or delete this file.
  #
  # A use case is one behaviour your code promises, and the proof that it keeps the promise.
  # This one is a DRAFT until it has a value tier, so it never blocks a gate. The prefix below
  # starts every id in this file: example.getting-started.
  prefix: example

  use_cases:
    - id: getting-started
      title: Learn what a use case holds

      # Choose a value tier to make this use case READY: critical, core or supporting.
      # value_tier: core

      intent: Show every part of a use case, so the first real one is easy to write.

      out_of_scope:
        - Anything a real use case of this project would say.

      scenarios:
        - id: read-it
          given:
            - This file is open.
          when:
            - A person reads what each part is for.
          then:
            - The person can write a use case of their own.

      # Each validation is a route to proof. A route with a procedure is checked by a person,
      # who runs the steps and records the result with: use-cases record
      validation:
        - id: manual-check
          type:
            kind: acceptance
          covers:
            - read-it
          procedure:
            steps:
              - Read this file from the top.
              - Copy it, change the ids and the words, and run use-cases validate.

  """

  /// One group, `smoke`, that selects the example by its prefix.
  static func groups(prefix: Namespace?) -> String {
    let selected = prefix.map { prefix in
      "\(prefix.text).example"
    } ?? "example"

    return """
    schema_version: 1

    groups:
      # A group is a named set of use cases, to look at or to gate together. This one holds the
      # example. Try: use-cases status --group smoke --gate
      smoke:
        description: The example use case.
        include:
          prefixes:
            - \(selected)

    """
  }

  /// The bridge settings as a template: valid, with no validation and one commented example to
  /// copy. The command is a placeholder; a real one is the person's to write.
  static let bridge = """
  schema_version: 1

  # How `use-cases verify --run` runs your tests. Add your own test command: remove the # from the
  # lines below and replace the placeholder command with the one that runs your tests.
  # validations:
  #   - id: unit-tests
  #     report: results.xml
  #     run: [your, test, command, "--junit-output={report}"]
  #     transformer: junit

  """
}
