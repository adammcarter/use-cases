extension ProcessRequest {
  /// The arguments the process is started with: every `{report}` placeholder, inside any
  /// argument, replaced by the report path as it is, with no quoting (chapter 14 §5). No other
  /// substitution happens, and braces that are not that placeholder, `${report}` among them,
  /// are passed on as written. Without a report path the arguments are unchanged.
  var launchArguments: [String] {
    guard let reportPath else {
      return arguments
    }

    return arguments.map { argument in
      var launched = argument

      // Back to front, so a replacement never moves a range still to be replaced.
      for placeholder in RunPlaceholder.found(in: argument).reversed() where placeholder.isKnown {
        launched.replaceSubrange(
          placeholder.range,
          with: reportPath,
        )
      }

      return launched
    }
  }
}
