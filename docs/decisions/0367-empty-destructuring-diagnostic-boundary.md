# Decision 0367: empty destructuring diagnostic boundary

## Status

Deferred as a diagnostic-only compatibility gap. The requested forms are not
valid jq destructuring patterns and must remain compile failures.

## Oracle evidence

The pinned jq suite marks both cases `%%FAIL`:

- `upstream/jq/tests/jq.test:548-551`: `. as [] | null`
- `upstream/jq/tests/jq.test:554-557`: `. as {} | null`

jq 1.8.1 reports an unexpected `]`/`}` with expected-token text and a compile
error. Odin also rejects both filters, but currently emits generic
`jq-odin: filter parse error`. Accepting either form would contradict jq.

## Source boundary

`parse_container` constructs empty array/object literal nodes
(`src/syntax/parser.odin:4143-4160`), while `as` destructuring requires at
least one collected pattern leaf in `try_parse_ordinary_pattern_binding`
(`src/syntax/parser.odin:671-678`). Pattern guards reject empty patterns
(`src/syntax/parser.odin:3380-3427,3491-3527`). No program/evaluator ABI is
involved because compilation must stop before instruction emission.

## Decision

Do not add empty-pattern Binding nodes or evaluator behavior. A future
diagnostic-focused lane may improve the parser error span and expected-token
formatting; that belongs to the syntax/diagnostic contract.
