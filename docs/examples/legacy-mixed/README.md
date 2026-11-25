# Legacy / Mixed-Language Use Cases Example

This example intentionally looks unlike a clean modern package.

It demonstrates that Use Cases can sit over a messy repository containing:

- C implementation
- JavaScript UI code
- shell scripts
- Python integration tests
- config and fixture resources
- a marker in the JavaScript
- manual file and range bindings for code that carries no marker
- existing tests not tied to any use case
- a procedural acceptance check
- strict `content-and-locator` freshness policy
- optional helpers in `use-cases-bridge.yml`

Resolved use case:

```text
legacyapp.auth.login
```

## Links without touching the code

Only `web/login.js` carries a marker. The C source, the audit script, and the Python integration test are linked from the use case YAML with manual bindings, so the legacy code stays exactly as it was.

## Helpers

`use-cases-bridge.yml` runs the integration test through pytest for `use-cases verify --run`, and reads the result with the `exit-code` transformer.

`exit-code` is a bundled transformer. It gives the whole-file `integration-script` link a pass when the command exits 0 and a fail otherwise. It needs the exit code, so it works only with `use-cases verify --run`.

`tests/js/login.spec.js` is deliberately not tied to the use case. It represents an existing legacy test that has not been adopted yet.

The point is not that this is a good architecture.

The point is that Use Cases does not require one.
