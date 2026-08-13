# Decision 0264: function-definition and call-frame contract

The remaining jq definition/call cases require a first-class contract rather
than extending textual module expansion. The current parser accepts one root
filter and explicitly rejects generic identifier calls (`src/syntax/parser.odin`
around lines 447-470 and 1570-1586). The compiler lowers one root into one
program (`src/compiler/package.odin` around lines 422-442), while the program
owns only instructions, operands, text, and root metadata (`src/program/package.odin`
around lines 367-387). Runtime variable lookup currently resolves binding
frames (`src/eval/evaluator.odin` around lines 1620-1643).

The eventual contract must carry ordered top-level definitions and a main root;
compile definitions into owned body entries keyed by name and arity; represent
calls with ordered argument subprograms; and add evaluator call frames that
retain lexical bindings, argument generator state, return continuation, and
recursion depth. Calls must resume across generator outputs and propagate
errors/catches without recursive Odin stack growth. Tail calls may reuse a frame
only after ordinary call semantics are validated.

The existing driver/module-loader textual expansion remains a compatibility
bridge for simple module cases, but it is not a substitute for this contract
and must not be broadened to claim closures, nested redefinitions, generators,
or recursion.
