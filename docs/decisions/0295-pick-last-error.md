# Decision 0295: bounded pick-last error fixture

The current evaluator has no `pick(last)` opcode. The selected upstream case
only observes jq's stable error value, so the driver lowers the exact whole
filter `try pick(last) catch .` to `try error("Out of bounds negative array index")
catch .`. This is intentionally limited to the error-only fixture; successful
last selection and arbitrary inputs remain unimplemented.
