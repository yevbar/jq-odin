# Decision 0212: preserve iterator errors as caught values

Status: accepted (2026-08-11).

jq's `try .[] catch .` returns the typed iterator diagnostic as a string,
including the input kind and compact value. The evaluator therefore owns an
allocated runtime key for `Cannot_Iterate`, which follows the existing runtime
error replay and cleanup contract.

Evidence: `upstream/jq/tests/jq.test:200`.

Scope is limited to the existing `.[]` field iterator. New continuation forms
remain out of scope.
