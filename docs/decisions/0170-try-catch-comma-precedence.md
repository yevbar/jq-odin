# Decision 0170: keep surrounding commas outside catch filters

## Scope

An unparenthesized `try ... catch ...` filter consumes binary and pipe
operators, but a comma at the same query level starts the surrounding stream.
Commas inside parentheses remain part of the catch filter. This preserves
multiple caught outputs such as the trim-family case in
`upstream/jq/tests/jq.test:1537`.

## Evidence

`compat/try-pipe-precedence.jq.test` covers both comma-separated catches and a
following pipe. The shard passes 2/2 against pinned jq 1.8.1; package checks,
the full Odin test suite, and the catalog pass count remain green. The catalog
increases from 186/522 to 187/522.

## Deferred

Dynamic generators, labels, assignment/update paths, and parenthesized
continuation forms remain outside this parser-precedence fix.
