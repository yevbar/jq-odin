# Walk filter AST lowering

Status: implemented for the bounded recursive-filter contract.

The pinned jq definition of `walk(f)` is a post-order recursive filter:
objects recurse through `map_values`, arrays through `map`, atoms through
identity, and the supplied filter runs after the child container is rebuilt
(`upstream/jq/src/builtin.jq:212-221`). The prototype recognizes `walk(filter)`
in the parser and constructs that definition directly in the syntax arena. It
creates a recursive `Call` edge to the generated body and keeps the supplied
filter as the final pipe child; no driver source rewrite or new evaluator
opcode is used.

The focused shard is `compat/walk-filter-postorder.jq.test`, covering empty
object/array pruning, array multi-output callbacks, object first-result
behavior, source-order preservation, and callback errors. Package checks,
Odin compilation, 86 evaluator tests, and the four-case pinned jq 1.8.1
compatibility shard pass on the integration candidate. The existing
`Map_Values` object traversal was corrected to consume entries in source order
so rebuilt objects retain jq's key order.

The lowering deliberately does not claim arbitrary user-defined `walk/1`
shadowing or a separate evaluator opcode; it uses the existing recursive Call,
Map, and Map_Values contracts and rejects malformed call shapes through normal
parser paths.
