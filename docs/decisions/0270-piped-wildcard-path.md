# Decision: bounded piped wildcard path continuation

## Context

The evaluator already supports static prefixes followed by a wildcard postfix
(`path(.a[])`) and wildcard identity pipes (`path(.[] | .)`). jq also accepts
the equivalent piped form `path(.a | .[])`, which previously fell through to
internal misuse despite being a direct composition of those two supported
shapes.

## Decision

Extend the dynamic path recognizer to combine a static left prefix with a
right-side empty-field wildcard. Keep the recognizer deliberately bounded: the
right side must resolve to an empty prefix plus wildcard, and the left side
must be static. Predicate or `map` continuations continue through the general
resumable path contract rather than being guessed here.

## Evidence

- `upstream/jq/tests/jq.test:1110-1128` records jq's generator-valued path
  cases, including the invalid `map(select(...))` forms that motivate this
  boundary.
- `compat/path-piped-wildcard.jq.test` exercises successful `try`-wrapped
  piped wildcard paths against the pinned jq oracle.

## Ownership

The recognizer returns allocator-owned path arrays. It destroys the temporary
right-side prefix before transferring the left prefix to the caller and
retains no borrowed values across evaluator steps.
