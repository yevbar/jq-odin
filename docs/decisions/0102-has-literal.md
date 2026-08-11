# Decision 0102: bounded literal `has`

Append a `Has` AST/opcode form for literal object keys and numeric array
indexes. Object membership uses the existing owned lookup API; array presence
checks a non-negative integral index against the current length. NaN and other
unsupported argument kinds return false in this bounded slice, matching the
literal test cluster at `upstream/jq/tests/jq.test:1687-1695`.

Dynamic arguments, negative indexes, null diagnostics, recursive `map`/path
compositions, and assignment semantics remain deferred. The implementation
adds no package import edge and preserves existing operand ownership rules.
