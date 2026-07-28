# JSON workstream

Own JSON text parsing, printing, and streaming input above the value package.

Start with evidence and fixtures for invalid UTF-8, escapes, embedded NUL,
number lexemes, multiple inputs, streaming errors, and exact output formatting.
Do not retain slices into temporary input buffers without an explicit lifetime
contract.

