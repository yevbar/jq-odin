# Decision 0386: bounded formal-filter call activation

## Scope

Build on Decision 0385's explicit `Parameter_Reference` marker with one
runtime path: a two-edge `Call` whose body is a single formal reference and
whose second edge is the argument filter. The evaluator retains that argument
instruction on the body frame and evaluates it against the callee input. Each
argument result is forwarded through the call continuation.

This is closure invocation, not value binding. Ordinary `$name` lookup still
uses the existing lexical binding walk (`variable_result`), while an un-routed
formal marker remains `Unsupported_Opcode`.

## Ownership and limits

The argument remains an immutable Program instruction edge; frame teardown owns
only input values. Generator-valued arguments naturally resume through the
existing frame continuation. This phase supports one formal reference only;
multiple formals, body composition around the formal, and recursive closure
environments remain deferred.

Source anchors: evaluator frame phase and retained argument fields are in
`src/eval/evaluator.odin:130-150` and `src/eval/evaluator.odin:312-325`;
activation is in `src/eval/evaluator.odin:8870-8895` and call dispatch in
`src/eval/evaluator.odin:11790-11820`.
