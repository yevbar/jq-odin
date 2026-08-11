# 0091: Add bounded `nan` and `infinite` constants

- Status: accepted
- Workstream: evaluator

## Context and evidence

jq accepts `nan` and `infinite` as zero-argument numeric filters. The oracle
exercises them in arithmetic and `isnan` cases at
`upstream/jq/tests/jq.test:689-693` and in JSON round-tripping at
`upstream/jq/tests/jq.test:2271-2278`.

## Decision

Append `Nan` and `Infinite` syntax/program discriminants to preserve existing
serialized forms. Lower both as operand-free builtins and return native
`math.nan_f64()` / positive `math.inf_f64(1)` values. Existing serializer and
comparison code already defines NaN and infinity behavior.

## Consequences and limits

The owned syntax, compiler, program, and evaluator packages change together.
Positive constants, NaN modulo behavior, and `isnan` parity are covered by the
focused shard. Unary `-infinite` remains unsupported until a Negate opcode
contract is deliberately designed; parser diagnostics and NaN payload parsing
are out of scope.

## Validation

Run the special-number oracle shard, pinned Odin build, parser/compiler tests,
and evaluator/program package tests. `make validate` may still stop on the
repository's inherited external source-pointer check.
