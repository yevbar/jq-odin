# Decision 0353: nested field-to-index filter updates

## Status

Implemented as the bounded `Static_Field_Index_Field_Update` contract.

## Evidence

The integrated bounded update `.[0].a |= {"old":., "new":(.+1)}` passes the
catalog case at `upstream/jq/tests/jq.test:1232` and the corresponding oracle
fixture. Literal nested assignment already works:

```text
.foo[2].bar = 1
{"foo":[11],"bar":42}
=> {"foo":[11,null,{"bar":1}],"bar":42}
```

The filter-valued variants now match jq:

```text
.foo[2].bar |= 1       => {"foo":[11,null,{"bar":1}],"bar":42}
.foo[2].bar |= empty   => {"foo":[11],"bar":42}
```

The same boundary appears in catalog case `jq.test:1236`, where
`def inc(x): x |= .+1; inc(.[].a)` requires parameterized filter calls and
currently reports unsupported module syntax.

## Implemented boundary

`Static_Field_Index_Update` owns `.foo[index] |= FILTER`,
`Static_Index_Field_Update` owns `.[index].foo |= FILTER`, and
`Static_Field_Index_Field_Update` owns `.foo[index].bar |= FILTER`. The new
opcode carries two field texts, one nonnegative index text, and one RHS child;
its continuation preserves selected-element ownership, nested-field deletion,
first-output cancellation, and root/field null synthesis. Textual rewriting or
routing through `Setpath` would lose these cardinality and error contracts.

## Contract and fixture

The append-only operand layout and continuation phases are covered by
`compat/field-index-field-filter-update.jq.test`, including missing/null
synthesis, out-of-range extension, empty/multi-output RHS, late errors, and
typed scalar/intermediate failures.
