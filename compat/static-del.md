# Static `del` lowering

This shard covers field and numeric-index `del` forms, including nested static
field/index chains. The parser lowers each single static path into the existing
literal `delpaths` array ABI, preserving copy-on-write deletion and ownership
in the evaluator. Comma path generators, slices, and dynamic indexes remain
outside this bounded contract.
