# Comma-separated generators in skip and nth

`skip` and `nth` now parse comma-separated generator expressions as a stream,
matching jq's existing continuation behavior. Dynamic count expressions and
broader generator combinators remain outside this slice.
