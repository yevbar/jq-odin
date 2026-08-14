# Decision 0308: coordinate-stable comma/slice deletion

`del(path_a, path_b, ...)` must resolve every selector against the same
pre-deletion input. Sequentially mutating the value between comma branches
changes negative indexes and slice bounds and diverges from jq (notably
`jq.test:1175`).

The bounded contract for static selectors is:

1. Preserve comma selectors as one Delpaths operation whenever a selector
   contains a literal slice; scalar-only legacy lowering may remain sequential.
2. Materialize each selector against an immutable snapshot, resolving negative
   indexes and omitted/clamped slice bounds at each container's original
   length.
3. Normalize selected leaves into a coordinate mask, deduplicate overlaps, and
   apply removals deepest-first and right-to-left within each array.
4. Keep dynamic indexes, computed paths, and generator-valued selectors
   deferred; unsupported forms must produce controlled evaluator misuse rather
   than silently falling back to sequential mutation.

This keeps the existing instruction ABI (selector instructions remain child
nodes of Delpaths) while introducing an evaluator-local selector/mask owner.

## Evidence fixture

The exact expected outputs are recorded in `compat/del-slice-mask.jq.test` for
the upstream cases at `jq.test:474` and `jq.test:1175`.
