# Callable filter frame contract

Status: prototype contract, implementation pending

The current driver expands `def` bodies into source text. That is useful for
bounded non-recursive compatibility cases, but it cannot implement jq's
declaration-time lexical visibility, recursive calls, or generator-valued
calls. The first real callable slice is `def f: . + 1; f` and must execute a
body through evaluator-owned frames.

## Vertical contract

1. **Parser** adds explicit `Definition` and `Call` nodes. A definition owns
   the name span, arity, body node, and a stable definition ordinal. A call
   refers to the name/arity and never substitutes source text.
2. **Compiler/program** stores a definition table on `Program`. Each entry
   contains the compiled body instruction root, name text, arity, and ordinal.
   The call instruction stores a definition-table index (or a resolved
   name/arity key during a validation pass). Definition bodies are compiled
   once and remain immutable after `Program` activation.
3. **Evaluator** activates a `Call_Frame` containing the caller resume
   instruction, callee body entry, selected definition ordinal, and lexical
   binding frame. `step` enters the callee; callee exhaustion pops exactly one
   frame and resumes the caller. Output values are streamed through the same
   iterator contract as any other instruction, so recursion and `empty` do
   not require source rewriting.

The frame transition prototype in `src/eval/call_frame_prototype.odin` and
its tests exercise push, peek, return, declaration-time snapshot, and bounded
overflow/underflow behavior. It deliberately is not connected to `Evaluator`
yet; the next implementation must add the program definition table and then
replace the prototype's fixed storage with evaluator-owned allocator state.

## Required probes before integration

- `def f: . + 1; f` on `2` → `3`
- `def f: f; f` → bounded recursion/runtime error, not host stack overflow
- `def f: ., empty; f` streams one output then reaches caller continuation
- `def f: 1; def f: 2; f` resolves the latest top-level definition while an
  earlier compiled body retains its declaration-time snapshot

Source facts: `src/syntax/parser.odin:1581-1586` documents that calls currently
have no AST/lowering contract; `src/driver/module_loader.odin` performs source
expansion; `src/eval/evaluator.odin:350-388` defines the address-stable evaluator
owner that will host the eventual frame stack.
