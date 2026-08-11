# 0092: Add zero-argument `any` and `all`

- Status: accepted
- Workstream: evaluator

## Context and evidence

The jq oracle directly exercises `[any,all]` with empty, truthy, falsey, and
mixed arrays at `upstream/jq/tests/jq.test:1077-1095`.

## Decision

Append `Any` and `All` syntax/program discriminants, lower them as operand-free
builtins, and evaluate the input array using jq truthiness: only `null` and
`false` are falsey. Empty arrays return false for `any` and true for `all`.
The evaluator copies and destroys each element before continuing, preserving
value ownership.

## Consequences and limits

Syntax, compiler, program, evaluator, and focused tests change together.
Parameterized generator/condition forms remain explicitly deferred because
they require a continuation contract; non-array diagnostics are deferred too.

## Validation

Run `compat/any-all.jq.test` against the pinned oracle/candidate, the pinned
Odin build, and package tests. `make validate` may stop on the known external
Oniguruma source-pointer mismatch after package tests pass.
