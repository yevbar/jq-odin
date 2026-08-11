# Decision 0175: support bounded string multiplication

## Scope

Binary multiplication now repeats a string by a numeric count in either
operand order. Positive fractional counts truncate, zero yields an empty
string, negative counts yield null, and oversized results raise jq's
`Repeat string result too long` message.

## Evidence

`compat/string-multiply.jq.test` passes 3/3 against pinned jq 1.8.1 and covers
the direct cases in `upstream/jq/tests/jq.test:1583-1603`. Existing numeric
multiplication remains unchanged.

## Limits and ownership

The repeated string is built in an allocator-owned `strings.Builder` and
transferred into a value. Dynamic generators, nonnumeric multiplication
diagnostics, and platform-sized results remain deferred.
