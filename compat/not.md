# `not` compatibility shard

The zero-argument `not` filter emits `true` only for `null` and `false`; all
other JSON values are truthy in jq. The parser recognizes `not` as
`Node_Kind.Not_Builtin`, and the evaluator emits the negated jq truthiness
classification through `Opcode.Not_Builtin`.

Run `tools/compat/jq_compat.py` with this test and its skip manifest against
the pinned jq oracle and Odin candidate. Expected result: one selected case,
one passing case.
