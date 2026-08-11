# Decision 0156: static `error("literal")` runtime contract

## Scope

Implement the bounded jq form `error("literal")`: a literal string argument
is compiled into the program and raises a terminal runtime error when reached.
The evaluator owns the error message bytes until terminal cleanup; `try`/`catch`
suppression observes the same runtime error and resumes the catch branch. The
driver borrows the retained message and the CLI emits it with jq's `jq: error:
<message>` framing.

## Ownership and cleanup

The error message is copied into evaluator-owned storage by the existing
`Runtime_Error.key` retention path. It remains valid through runtime-error
replay and destruction retries, then is released with the evaluator. No
temporary allocator data escapes evaluation.

## Evidence

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:1447-1451` establish the
runtime-error and suppression contract. This lane checks `error("foo")`'s
diagnostic/status and static `try error("foo") catch .` plus a literal catch
replacement, with the evaluator retaining the message until it is transferred
to the catch input.

## Deferred

Dynamic expressions, non-string arguments,
`halt`, `debug`, and exact source-location formatting beyond the existing driver
contract remain deferred.
