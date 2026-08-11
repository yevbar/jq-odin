# Decision 0188: literal variadic `bsearch`

## Scope

Accept comma-separated numeric literal needles in `bsearch(0,1,2,3,4)` and
lower them to a sequence of the existing single-needle `Bsearch` instructions.
This preserves the evaluator's ownership and binary-search contracts while
matching jq's multiple outputs.

## Evidence

The jq 1.8.1 case at `upstream/jq/tests/jq.test:1789-1795` establishes the
five literal needles and their output sequence.

## Deferred

Dynamic or object variadic needles, generator-valued arguments, and detailed
non-array diagnostics remain deferred.
