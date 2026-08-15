# Decision 0368: callable filter-valued update boundary

## Status

Deferred pending a real callable-update ABI. The existing bounded callable
identity slice supports `def id(x): x |= .; id(.a)`, but must not be extended by
rewriting `x |= .+1` to a scalar arithmetic body.

## Oracle evidence

Pinned jq 1.8.1:

```text
printf '{"a":1,"b":2}\n' | jq -c 'def inc(x): x |= .+1; inc(.a)'
{"a":2,"b":2}
```

The attempted parser/program/compiler extension compiled packages but the
candidate failed at filter compilation for all `inc` probes. The extension
was discarded; no partial source is integrated.

## Source boundary

The current two-edge `Call` ABI evaluates the argument child as values before
activating the callee. The identity specialization instead retains a literal
field key and caller root through a dedicated `Parameter_Identity_Update`
opcode. Arithmetic RHS state requires a new opcode payload carrying the RHS
instruction/number and complete compiler validation, evaluator continuation,
cardinality, empty-stream, error, and ownership handling.

## Decision

Do not broaden the identity route or use driver textual rewriting. The next
implementation phase must add a first-class callable filter-update payload and
resume semantics, then validate literal and generator arguments separately.
