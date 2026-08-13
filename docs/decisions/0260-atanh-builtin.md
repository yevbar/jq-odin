# Decision 0260: bounded `atanh` builtin

Add jq's zero-argument `atanh` as an append-only syntax/program opcode and
evaluator builtin. Numeric values use Odin's native `math.atanh`; values outside
the real domain produce jq-compatible null/error behavior through the existing
numeric builtin boundary. Dynamic calls and platform-sensitive final-digit
formatting remain deferred. Evidence: `upstream/jq/src/libm.h:32-34`.
