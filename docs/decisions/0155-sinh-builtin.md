# Decision 0155: bounded `sinh` builtin

## Scope

Add jq's zero-argument `sinh` filter for numeric inputs. The parser, AST,
compiler opcode, evaluator, and shape tests are updated together. The evaluator
uses Odin `core:math.sinh` on the f64 value.

## Evidence

The jq 1.8.1 oracle emits `-1.1752011936438014`, `0`, and
`1.1752011936438014` for `-1 | sinh`, `0 | sinh`, and `1 | sinh`; these cases
are captured in `compat/sinh.jq.test`.

## Deferred

Non-number diagnostics, dynamic/parameterized forms, near-overflow behavior,
and platform-dependent interior floating-point precision remain outside this
bounded lane.
