# Decision 0242: bounded static numeric field assignment

Implement `.field = NUMBER` as a dedicated append-only syntax node and program
opcode. The evaluator accepts object inputs with an existing field, constructs an
owned numeric value from the parser's spelling, and replaces that member while
preserving unrelated entries. This deliberately excludes general jq path
assignment, missing-field creation, arrays, dynamic keys, generators, and all
other assignment operators (including negative literals); those require
separate continuation and ownership contracts.
