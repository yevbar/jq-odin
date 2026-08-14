# Decision 0325: defer first-class `group_by` pending keyed materialization

## Audit

The catalog case at `upstream/jq/tests/jq.test:1639-1645` combines nested
`sort_by`, multi-key sort filters, and `group_by` with both a field key and an
arithmetic key expression. The current candidate handles only the narrow
whole-filter `sort_by(.field)` bridge in `src/driver/package.odin:381-413`.
Composed filters and `group_by` return parse errors; no implementation was
added in this lane.

Pinned jq defines both operations through keyed materialization:
`upstream/jq/src/builtin.jq:5-6` expands `sort_by(f)` and `group_by(f)` as
`_impl(map([f]))`. The C implementation pairs every input object with its
key, performs a stable key sort (`upstream/jq/src/jv_aux.c:663-712`), and
groups adjacent equal keys (`upstream/jq/src/jv_aux.c:714-740`). Key filters
are generators, so `[f]` must retain zero-to-many outputs and preserve their
ordering before sorting.

## Boundary

Do not extend the driver string rewrite or approximate `group_by` with a
plain `sort`/`unique` composition. The existing `.Sort` opcode only sorts the
input array (`src/eval/evaluator.odin:6386-6391`), and the current IR has no
keyed pair storage, key-filter child continuation, stable tie index, or
adjacent-equality grouping step. A textual rewrite would also fail for nested
composition, dynamic arithmetic keys, generator-valued keys, and key/runtime
errors while obscuring ownership of materialized values.

## Smallest next contract

Implement first-class unary `sort_by(f)` before `group_by`:

1. Parse `sort_by(f)` as a syntax node retaining `f` as a child filter, rather
   than rewriting source text. Lower it to a keyed-materialization operation
   that evaluates `f` for each array element and stores an owned key stream and
   original element with a stable input index.
2. Reuse the existing value comparator and constructor stream machinery for
   stable key sorting. Define cleanup for key streams and original elements on
   child errors, allocation failures, and empty key streams.
3. Cover `sort_by(.b)`, `sort_by(.a, .b)`, nested composition, generator keys,
   non-array input diagnostics, and key-filter runtime errors against jq.
4. Add `group_by(f)` only after the keyed pair representation is proven: sort
   pairs by key, compare adjacent keys with jq equality, and emit owned groups.

Evidence: `upstream/jq/tests/jq.test:1639-1645` and source lines cited above.
