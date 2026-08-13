# Top-level zero-argument definitions and calls

## Decision

The first general function contract supports top-level jq definitions of the
form `def name: body;` and zero-argument calls `name`. Definitions are compiled
into an owned definition table on the `program.Program`; calls resolve to a
definition index during lowering. A call executes the definition body with the
caller's current input and returns every body output through the evaluator's
existing resumable stream machinery.

This slice intentionally excludes parameterized definitions, nested lexical
definitions, closures, and dynamic call names. Recursive top-level calls are
allowed, but the evaluator applies an explicit activation-depth limit and
reports a runtime misuse when it is exceeded rather than overflowing the host
stack.

## Ownership and boundaries

- `syntax` owns source `Definition` and `Call` nodes. Definition names and
  bodies remain parser-owned until lowering.
- `compiler` collects top-level definitions before lowering bodies, so forward
  references and recursion resolve without textual expansion.
- `program` owns definition names and body instruction indices in the same
  address-stable allocation as instructions, operands, and text.
- `eval` owns call activation frames and their continuation state; it does not
  import `compiler`.

The contract follows the package graph in `docs/architecture/package-graph.md`
and preserves jq's generator semantics by resuming the called body as an
ordinary child frame. No Odin recursion or module-loader substitution is used.

## Evidence

The previous parser accepted one filter only (`src/syntax/parser.odin:516-543`)
and rejected generic calls (`src/syntax/parser.odin:1570-1586`). The program
owned only one root instruction (`src/program/package.odin:367-387`), while
the evaluator already models explicit continuation frames
(`src/eval/evaluator.odin:94-196`). This decision extends those contracts in
the smallest end-to-end direction needed for recursive jq definitions.
