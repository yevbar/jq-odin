# Decision 0281: repeated `elif` chains

Repeated `elif` arms are represented as nested `If` nodes in the else branch.
The parser accepts an omitted final `else` and emits an Identity fallback,
matching jq's conditional semantics. No new opcode or evaluator frame is
needed. The implementation is intentionally limited to parser lowering;
runtime error-message parity in conditional branches remains separate.
