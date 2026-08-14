# Decision 0326: defer keyed `sort_by` until stable-key materialization exists

## Audit

The current integration head `a0bdcec5` still has only the bounded driver
bridge documented at `src/driver/package.odin:381-413`: it rewrites a complete
`sort_by(.field)` source string into `map([.field,.]) | sort | map(.[1])`.
Composed filters, generator keys, and `group_by` remain outside that bridge.

I prototyped the smallest source-preserving AST lowering for unary
`sort_by(f)` using existing `Map`, array-constructor, `Sort`, and `Index` nodes.
The pinned oracle exposed a correctness boundary before the prototype was
committed: the existing `Sort` compares the entire `[key, object]` array. For
equal keys this compares the object payload, not the original input index, and
therefore violates jq's stable tie rule.

Evidence from the pinned jq implementation:

* `upstream/jq/src/builtin.jq:5` defines `sort_by(f)` as
  `_sort_by_impl(map([f]))`, so key streams must be materialized per item.
* `upstream/jq/src/jv_aux.c:663-675` stores an explicit `index` and uses it as
  the tie-breaker when `jv_cmp(key) == 0`.
* `upstream/jq/src/jv_aux.c:677-712` sorts paired objects by key while retaining
  the original object, rather than sorting the pair value lexicographically.
* The catalog target and equal-key records are at
  `upstream/jq/tests/jq.test:1639-1645`.

The uncommitted prototype was reverted; this branch contains no parser,
compiler, driver, or evaluator changes.

## Smallest sound next contract

Add a dedicated keyed-materialization representation before parser lowering:

1. A first-class unary `sort_by(f)` AST/program instruction owns the key filter
   child and materializes `(key stream, original value, input index)` entries.
2. The evaluator runs the key child once per input element, preserving zero,
   one, and many outputs and propagating key errors in input order.
3. A keyed comparator compares only the materialized key, then the stored index;
   it must never compare the original value as a tie-breaker. Cleanup must cover
   key streams, original values, and partially-built entries on all failures.
4. Only after this instruction passes equal-key, generator-key, and error-order
   fixtures should `group_by(f)` reuse the entries to group adjacent jq-equal
   keys. Multi-key `sort_by(.a, .b)` remains a separate key-stream contract.

This is the smallest implementable contract that satisfies jq's stable-order
requirement without textual rewriting or silently changing existing `sort`.
