# Decision 0358: binding-aware path assignment remains a shared ABI boundary

## Status

Deferred after auditing `upstream/jq/tests/jq.test:2088`:

```jq
(.a as $x | .b) = "b"
```

No implementation is made on the existing assignment lane.

## Evidence

The pinned jq 1.8.1 oracle transforms `{"a":1,"b":2}` into
`{"a":1,"b":"b"}`. The current Odin candidate rejects the `=` form during
parsing. Its non-assignment binding form `.a as $x | .b` does work and emits
`2`, and the existing `|=` identity form preserves the input, so this is a
path-capture gap rather than a general lexical-binding failure.

The assignment parser admits only literal field/index paths and the bounded
generated-path shapes (`src/syntax/parser.odin:3195-3214`); a `Binding` node is
not admitted. The evaluator's path materializers accept only identity,
field/index, fork/sequence, or callable wrappers of those forms
(`src/eval/evaluator.odin:2675-2725`). Ordinary binding frames evaluate the
left generator to a value, retain it in `binding_value`, then run the body
with the original input (`src/eval/evaluator.odin:4869-4912`). A path update
needs the body to produce owned path arrays while preserving the lexical value
for `$x`; treating the binding's scalar body output as a path either rejects
the query or misclassifies a value as an assignment path.

## Boundary and required contract

Supporting this case requires a binding-aware path continuation across parser,
program, and evaluator layers: capture each binding value, evaluate the body
as a path-producing filter, retain zero/one/many path outputs, and apply the
RHS with jq's copy-on-write and error-stream ordering. It cannot be safely
implemented by admitting `Binding` to the literal-path predicate or by
rewriting the source to `.b = ...`, because future forms can reference `$x`
inside the path and must preserve lexical scope and stream cardinality.

## Next bounded case

Schedule a dedicated cross-package vertical slice beginning with the exact
unused-binding form above, then add a companion that references `$x` in a
literal path component. The slice should introduce an explicit binding/path
capture contract before expanding to generator-valued bindings or compound
updates.
