# Decision 0213: recursive object multiplication

Status: accepted (2026-08-11).

For `object * object`, jq recursively merges nested object values and uses the
right-hand value for non-object collisions. The evaluator constructs an owned
result by cloning both operands and recursively merging matching objects;
borrowed operands are never mutated.

Evidence: `upstream/jq/tests/jq.test:1713-1725`.

Non-object multiplication remains governed by the existing numeric/string
contract.
