# Decision 0330: `INDEX/2` generator form is outside the current index ABI

- Status: proposed
- Date: 2026-08-14
- Workstream: syntax/compiler/eval

## Evidence

The jq 1.8.1 compatibility case at `upstream/jq/tests/jq.test:2047-2049`
evaluates `INDEX(range(5)|[., "foo\(.)"]; .[0])` on `null`. The pinned jq
oracle emits `null` followed by an object whose keys `0` through `4` map to
`[n,"foon"]`.

The Odin candidate rejects this filter at parse time (`jq-odin: filter parse
error`). Lowercase `index`, `rindex`, and `indices` are recognized only in the
single-argument call branch (`src/syntax/parser.odin:1803-1804`), and their
validation admits strings, numbers, and static array literals but not a
generator (`src/syntax/parser.odin:1935-1969`). The call kind is assigned only
for lowercase spellings (`src/syntax/parser.odin:1985-1992`).

Even if parsing were extended, the current IR lowers the family to one child
operand (`src/compiler/package.odin:1171-1185`). The evaluator materializes that
child as one literal needle and calls `search_result`
(`src/eval/evaluator.odin:9020-9039`); it has no continuation for a needle
stream, a key filter, or the object-building cardinality of `INDEX/2`.

## Decision

Do not add a parser alias or textual rewrite. Supporting this case requires a
cross-package `INDEX/2` contract: syntax for uppercase two-argument calls,
program/compiler operands for two generators, evaluator continuations that
materialize each first-filter output and run the key filter, and owned object
accumulation across zero/many outputs and runtime errors. That is broader than
the bounded existing-IR builtin ABI and must be designed as a dedicated
workstream.

## Validation

The candidate was built with Odin vet and warnings-as-errors. The pinned oracle
probe passed with the expected five-entry object; the candidate probe produced
the parse error above. No source changes beyond this decision are required.
