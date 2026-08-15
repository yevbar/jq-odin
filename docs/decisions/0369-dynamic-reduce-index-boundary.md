# Decision 0369: resumable dynamic-index Reduce boundary

## Boundary

The jq compatibility case at `upstream/jq/tests/jq.test:484-492` is:

```jq
reduce range(65540;65536;-1) as $i ([]; .[$i] = $i)|.[65536:]
```

jq returns `[null,65537,65538,65539,65540]`; the minimal form
`reduce range(3;0;-1) as $i ([]; .[$i] = $i)` returns `[null,1,2,3]`.

## Audit evidence

The current parser assignment gate (`src/syntax/parser.odin:3190-3213`)
accepts only literal RHS nodes for `Dynamic_Index_Assign`, so `$i` is rejected
before compilation. An isolated parser allowance plus a synchronous evaluator
loop can reproduce the two exact outputs, but it is not a valid implementation:

- `reduce range(3;0;-1) as $i (null; .[$i] = $i)` must return
  `[null,1,2,3]` but the prototype reaches internal misuse;
- generator-valued RHS, comma/multi-output RHS, and computed keys require
  stream cardinality and late-error handling absent from the prototype;
- the loop cannot suspend across key/RHS outputs or allocator retry, and does
  not preserve a binding frame while a child continuation runs.

The existing dynamic assignment frame (`src/eval/evaluator.odin:8415-8430,
11799-11860`) materializes key/RHS streams but has no Reduce binding linkage.
The Reduce evaluator (`src/eval/evaluator.odin:11171-11400`) handles literal,
pattern, identity, and bounded arithmetic shapes synchronously. Array extension
itself is available transactionally in `src/value/array.odin:404-487`.

## Required staged ABI

1. Permit variable key/RHS children in a typed dynamic-assignment instruction,
   preserving existing literal diagnostic behavior.
2. Add a `Reduce_Assign` frame that retains the accumulator, bound name/value,
   generator cursor, key stream, RHS stream, and resumable apply cursor.
3. Route every key/RHS output through copy-on-write `array_set_take` (and the
   corresponding object/string error paths), transferring displaced and error
   ownership on success, suppression, retry, and termination.
4. Add fixtures for scalar/null seeds, large offsets, zero/many RHS outputs,
   computed keys, typed failures, and optional/try continuation before merging.

No source implementation is merged for this case; the exploratory prototype was
fully reverted.
