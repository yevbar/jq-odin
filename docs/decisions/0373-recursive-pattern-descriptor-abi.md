# Decision 0373: recursive destructuring pattern descriptors

Status: accepted structural phase; evaluator capture activation remains deferred.

Alternation branches whose object/array pattern contains a nested container now
retain an explicit `Pattern_Descriptor` node. The compiler lowers that node to a
`Pattern_Descriptor` opcode with one child operand, while the surrounding
`Alternation` retains producer, body, and linked branch operands. Existing simple
array alternation and specialized simple-object permutations are unchanged.

The exact jq.test:929 shape parses and lowers structurally:

```jq
.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f |
  [$a, $b, $c, $d, $e, $f]
```

Focused parser/compiler tests assert the descriptor node and operand. The evaluator
returns `Unsupported_Opcode` when a descriptor branch is routed, because recursive
capture matching still needs branch-local null initialization, snapshot/rollback,
and committed variable lookup. This phase therefore does not claim runtime 929
compatibility or rewrite the source into nested `Try`/`Binding` nodes.

Evidence: descriptor construction is in `src/syntax/parser.odin:1235-1255`, recursive
dispatch at `src/syntax/parser.odin:3750-3760`, compiler lowering at
`src/compiler/package.odin:969-975` and `src/compiler/package.odin:1371-1376`, and
evaluator deferral at `src/eval/evaluator.odin:8845-8846`.
