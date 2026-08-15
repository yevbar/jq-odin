# Decision 0341: dynamic index assignment contract

## Boundary

The remaining jq.test:2044 case, `(.[{}] = 0)?`, cannot be implemented by
accepting the bracket syntax alone. The current parser already represents a
dynamic read as an `Index` node with a child key filter, while assignment
lowering only accepts numeric static indexes or literal `Setpath` paths.
`Setpath` currently materializes only string/number path components and its
failure result is a boolean, so it cannot preserve the distinct jq outcomes
for null/array slice-index errors, object-with-object errors, optional
suppression, and parenthesized `?` continuation.

## Required vertical contract

1. Preserve the index key as a child instruction and evaluate it against the
   original input before mutation.
2. Carry a resumable update frame with zero/one/many key and RHS outputs;
   `?` must suppress only the resulting runtime error, not parser failure.
3. Apply copy-on-write updates for string and integer keys, and emit jq's
   typed diagnostics for object/array/number/null mismatches.
4. Keep parenthesized assignment frames resumable so postfix optional and pipe
   suffixes are parsed after the assignment node is complete.
5. Transfer or destroy key, RHS, displaced, and error values on every retry,
   suppression, and allocator-failure path.

## Evidence

The parser's dynamic read construction is in `src/syntax/parser.odin`
(`append_postfix`, dynamic bracket branch). Static assignment dispatch is in
the same file's `parse_pipe` assignment section. Compiler/program operand
contracts are in `src/compiler/package.odin` and `src/program/package.odin`;
the evaluator's dynamic read continuation is `Index_Child_Active` and
`Index_Key_Active` in `src/eval/evaluator.odin`, while literal update paths use
`set_path_value` and `Setpath`.

The exact jq oracle probe is:

```sh
printf 'null\n[]\n{}\n1\n"x"\n' | jq -c '(.[{}] = 0)?'
```

This contract intentionally defers generator-valued RHS streams and nested
path updates until the same resumable update machinery exists for all path
components.
