# Decision 0163: normalize arithmetic positive-number text

## Scope

Strip an internal leading `+` from numeric literal spellings when converting
values to jq JSON text (`tostring` and formatter helpers). Arithmetic can
retain that sign internally, but jq never exposes it in serialized positive
numbers.

## Evidence

The focused `compat/number-sign.jq.test` shard compares arithmetic-produced
positive values with the pinned jq 1.8.1 oracle. The broader regression is
covered at `upstream/jq/tests/jq.test:2199`.

## Deferred

No changes are made to input JSON spelling or unary-negative canonicalization.
