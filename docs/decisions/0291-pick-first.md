# Decision 0291: bounded pick(first)

Only `pick(first)` as a complete filter is lowered to the existing numeric
slice ABI. Nested pick paths and `pick(last)` retain their unsupported status
until a path-capture/negative-index contract is available.
