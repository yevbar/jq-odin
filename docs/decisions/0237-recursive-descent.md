# Decision 0237: bounded recursive-descent continuation

Standalone `..` is represented by append-only `Recurse` AST and program
discriminants. The instruction has no operands. It does not expose the upstream
`recurse` function or add label, assignment, or dynamic-call machinery.

The evaluator implements preorder depth-first traversal with the existing
explicit frame arena. A recurse frame first transfers an owned clone of its
input to the output stream. It then copies one array element or object value
into a child frame and waits for that complete subtree before selecting the
next sibling. Scalar and empty-container frames have no children and finish
after their initial output. This is the direct observable behavior of
upstream's `def recurse(f): def r: ., (f | r); r` and
`def recurse: recurse(.[]?)` (`upstream/jq/src/builtin.jq:36-39`), including
the pinned `[..]` order and cardinality (`upstream/jq/tests/jq.test:187-189`).

Each frame owns its input `Value`; container element-copy procedures create the
child owner, and ordinary frame exhaustion destroys it. Traversal uses no native
recursion and adds no package edge or public evaluator type. The new opcode is
appended after `Slice`, preserving every prior serialized discriminant.
