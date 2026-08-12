# Decision 0235: postfix optional in map query streams

## Context

jq parses each function argument as a complete `Query`, whose comma operator
combines filters (`upstream/jq/src/parser.y:324-345,745-756`). Empty-bracket
postfix iteration selects `EACH` or `EACH_OPT` according to its trailing `?`,
for both `term[]?` and `term.[]?` spellings
(`upstream/jq/src/parser.y:610-620`). The pinned catalog combines ordinary
`try .a[] catch .` branches with `.a[]?` and `.a.[]?` branches inside one
`map` argument (`upstream/jq/tests/jq.test:199-202`).

The source AST already represents comma as `Comma`, postfix suppression as
`Optional`, and empty-bracket iteration as the existing empty-name `Field`.
The compiler already lowers those nodes to `Fork`, `Optional`, and `Field`, and
the evaluator already distinguishes caught ordinary iterator errors from the
empty stream produced under `Optional`. The failure was that the bounded call
parser stopped a `map` argument at its first top-level comma.

## Decision

Parse `map` and `map_values` arguments through the complete existing comma
query boundary. Preserve their existing special closing-delimiter handling so
nested bindings remain inside the call. Do not introduce an opcode, AST kind,
continuation, assignment path, or dynamic control-flow form.

The focused parser test retains two `Try` and two `Optional` nodes under one
`Map` child stream. The evaluator test independently locks the existing
runtime contract: ordinary iteration adjacent to `try` produces the typed jq
diagnostic, while the corresponding postfix-optional iteration exhausts. The
compatibility fixture covers `.a[]?`, `.a.[]?`, and their jq catalog ordering
beside both try branches.

## Consequences

Comma-separated map child filters now reach the compiler and evaluator through
their already-supported `Fork` contract. This slice remains read-only and
static: assignments, dynamic index expressions, and new control-flow lowering
are deferred.
