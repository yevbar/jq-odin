# Decision 0229: lower select through existing conditionals

`select(f)` is lowered to `if f then . else empty end`, matching jq's builtin
definition while reusing the existing resumable conditional and empty paths.
This avoids adding a second predicate-consumer continuation protocol.
