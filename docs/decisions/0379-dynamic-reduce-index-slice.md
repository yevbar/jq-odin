# Decision 0379: bounded dynamic-index Reduce slice

## Scope

The parser and evaluator now carry one narrow reducer update shape:

```jq
reduce range(START;END;STEP) as $name ([]; .[$name] = $name)
```

`START`, `END`, and `STEP` must be literal integral numbers; the seed must be
the literal empty array; both the key and RHS must be the reducer binding name.
The evaluator applies each generated number through the existing transactional
`set_path_value` array path, preserving jq's null-fill growth and descending
range order. This covers jq.test:490 and a small regression probe.

## Boundary

This is a synchronous, structurally guarded first slice. Arbitrary key/RHS
streams, computed bounds, non-array seeds, nested paths, `try`/optional
continuations, and allocator-retry suspension remain deferred to a dedicated
resumable Reduce_Assign frame. The parser's variable RHS admission is consumed
only by the guarded reducer branch; the existing Dynamic_Index_Assign frame
continues to validate and apply general root key/RHS streams.

## Evidence

- `src/syntax/parser.odin:3410-3418` admits a variable RHS for root dynamic
  assignment while preserving the existing base/key guard.
- `src/eval/evaluator.odin:11390-11500` validates the Reduce generator, binding
  names, literal integral bounds, empty-array seed, and variable key/RHS before
  applying copy-on-write updates.
- `src/eval/evaluator.odin:3324-3360` is the shared `set_path_value` helper that
  extends arrays with nulls and transfers ownership transactionally.
- `upstream/jq/tests/jq.test:484-492` expects
  `[null,65537,65538,65539,65540]` for the large-offset case.

Focused fixture: `compat/reduce-dynamic-index.jq.test` (2 cases).
