# Decision 0169: retain fixed builtin runtime messages

## Scope

Populate the evaluator's owned `Runtime_Error.key` for the fixed jq messages
from non-datetime `strftime` and non-string `trim`/`ltrim`/`rtrim` inputs. This
keeps the existing driver/evaluator ownership contract and makes caught errors
observable instead of an empty string.

## Evidence

The focused `compat/runtime-error-keys.jq.test` shard compares both messages
against pinned jq 1.8.1. The full catalog gains the invalid datetime case at
`upstream/jq/tests/jq.test:1826`.

## Deferred

Parameterized error wording for other builtins, dynamic values, and exact
diagnostics for malformed JSON remain deferred.
