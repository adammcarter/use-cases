# ADR 038: One Swift package, four modules, dependencies one way

## Status

Accepted - 2026-10-17

## Context

The real build is Swift (ADR 036), a new build held to exactly the approved design (ADR 037). The MCP server is one verb of the command line (`use-cases mcp`, chapter 20), so the package takes the CLI-wrapper shape.

## Decision

- **One Swift package, four modules:**
  - `UseCasesCore`: the design itself (models, the services each chapter specifies, the strict YAML reader, paths and patterns, and the guides as a resource). It knows nothing about MCP or the command line.
  - `UseCasesCLI`: the commands, built with Swift Argument Parser, `mcp` among them.
  - `UseCasesMCP`: the tools, as a catalogue a test can read as data.
  - `use-cases`: the executable, wiring only.
- **Dependencies point one way:** the core is used by the CLI and the MCP surface, and both by the executable.
- **Every module has its own test module,** with the same folders inside; warnings are errors in every target.
- **Beside the package, unchanged in kind:** the plugin (its four skills, manifest and MCP configuration) and the transformers (separate programs, chapter 10).
- **Each tool call still runs its command as a separate process** (ADR 027): the package layout changes nothing about how the design behaves.

## Consequences

- Good: each chapter maps to a place in the core, so the code can be checked against the specification chapter by chapter.
- Good: the core is tested without a command line or a server, and the whole is tested by the acceptance suite (ADR 037).
- Cost: four modules to keep in step where one would compile.

## Considered Options

- **One module:** simpler, but the MCP surface and the commands could reach into each other and the core, and lose the seams that let each be tested alone.
- **A separate package per module:** more isolation, but versioning four packages for one product.

## Related Links

- ADR 036, ADR 037, ADR 027
- `docs/architecture.md`
