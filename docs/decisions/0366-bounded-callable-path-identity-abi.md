# Bounded callable path identity-update ABI

- Status: accepted bounded phase
- Date: 2026-08-15
- Workstream: language, program, compiler, evaluator, and driver

## Context and evidence

jq treats a filter-valued parameter as a path-producing computation, not as a
scalar argument. The upstream compatibility fixture uses
`def inc(x): x |= .+1; inc(.[].a)` and expects each selected object field to be
updated in place (`upstream/jq/tests/jq.test:1236-1238`). The VM preserves the
caller root and path stack across `PATH_BEGIN`/`PATH_END`, restoring the prior
root after path capture (`upstream/jq/src/execute.c:629-672`).

## Decision

For the first executable phase, syntax emits `Parameter_Identity_Update` only
for the declaration parameter in the exact body `x |= .`. The driver routes a
call only when its argument is a literal field filter (`.field`, with an
identity base); scalar, dynamic, and generator arguments remain unsupported.
The compiler lowers the marker to a zero-operand `Parameter_Identity_Update`
opcode. On call activation, the evaluator retains the caller root and borrows
the sealed program's field-name text in the call frame instead of evaluating
the argument to a scalar. The callee applies identity update semantics to that
root, including null-root object creation, missing-field null insertion,
typed non-object errors, and one-shot completion of the specialized call.

The call frame marks this path activation as complete after the callee stream;
it must not resume the ordinary argument generator edge, which would duplicate
outputs. The borrowed key remains valid only while the sealed Program is live;
no frame owns or frees program text.

## Alternatives

- Textual expansion was rejected because it loses call-frame ownership and
  makes future cardinality and error behavior impossible to validate.
- Passing the evaluated scalar argument was rejected because `.a`'s path and
  caller root are lost.
- General filter-valued arguments and multi-path updates remain deferred until
  a resumable path-stream ABI is available.

## Consequences

The syntax, program, compiler, evaluator, and driver packages share the new
marker/opcode contract. The evaluator owns only cloned root values; the field
key is a borrowed view into the immutable sealed Program. Future phases must
extend the same continuation state for generator cardinality, `empty`, dynamic
indexes, and nested path updates rather than widening this specialization by
source rewriting.

## Validation

`compat/callable-path-identity-update.jq.test` passes all six cases against the
pinned jq oracle. `make check-packages`, the 344 evaluator tests, CLI build,
and timeout-bounded single- and multi-input probes pass. The exact head passed
the independent adversarial semantic/ownership review.
