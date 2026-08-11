# Decision 0187: bounded named `strftime` numeric timestamps

## Scope

Extend the existing UTC `strftime` evaluator with the literal format
`%A, %B %d, %Y` for numeric Unix timestamps. The conversion is UTC and
discards fractional seconds as jq's timestamp path does.

## Evidence

The direct jq 1.8.1 case at `upstream/jq/tests/jq.test:1809-1811` establishes
the numeric timestamp and named weekday/month output contract.

## Deferred

Other format directives, local-time behavior, short or malformed datetime
arrays, and sibling date converters remain outside this bounded lane.
