# Defined-or fallback

The `//` binary operator is lowered to an append-only opcode. Null and false
left outputs evaluate the right fallback; truthy left outputs short-circuit.
The bounded shard covers scalar fallback. Error suppression with defined-or
requires a separate precedence/continuation follow-up.

Evidence: `upstream/jq/tests/jq.test:1447-1451,1472`.
