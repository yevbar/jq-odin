# Decision 0353: nested field-to-index filter updates remain deferred

## Status

Deferred pending a dedicated parser/program/evaluator continuation contract.

## Evidence

The integrated bounded update `.[0].a |= {"old":., "new":(.+1)}` passes the
catalog case at `upstream/jq/tests/jq.test:1232` and the corresponding oracle
fixture. Literal nested assignment already works:

```text
.foo[2].bar = 1
{"foo":[11],"bar":42}
=> {"foo":[11,null,{"bar":1}],"bar":42}
```

The filter-valued variants remain parser failures in the current candidate,
while jq produces the following results:

```text
.foo[2].bar |= 1       => {"foo":[11,null,{"bar":1}],"bar":42}
.foo[2].bar |= empty   => {"foo":[11],"bar":42}
```

The same boundary appears in catalog case `jq.test:1236`, where
`def inc(x): x |= .+1; inc(.[].a)` requires parameterized filter calls and
currently reports unsupported module syntax.

## Current boundary

`Static_Field_Index_Update` owns `.foo[index] |= FILTER`, and
`Static_Index_Field_Update` owns `.[index].foo |= FILTER`; neither represents a
field → index → field path. Adding this shape requires a new AST/program opcode
with two text keys and one index, plus evaluator state that preserves the
selected array element, nested field replacement, first-output cancellation,
empty deletion, missing/null synthesis, scalar diagnostics, and ownership of
rebuilt containers. Textual rewriting or routing through `Setpath` would lose
these cardinality and error contracts.

## Required contract before implementation

Define an append-only `Static_Field_Index_Field_Update` operand layout and
continuation phases, then cover existing/missing/null nested fields, out-of-range
array extension, empty and multi-output RHS, late errors, and typed failures on
scalar intermediate values against the pinned jq oracle.
