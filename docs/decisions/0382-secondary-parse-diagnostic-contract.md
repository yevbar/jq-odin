# Secondary parse diagnostics

## Decision

`syntax.Parse_Error` may carry one additional borrowed span/message pair for
parser constructs where jq reports a primary syntax error plus a targeted
follow-up diagnostic. The driver propagates that pair without allocation, and
the CLI emits both findings only when the parser marks the secondary payload.
Existing single-diagnostic errors remain unchanged.

## Evidence

`{1+2:3}`, `{1-2:3}`, and `{1*2+3:4}` now match jq's two diagnostics and
source carets. Literal `{1:3}` retains the object-key type diagnostic;
`{1|2:3}` and parenthesized `{(1+2):3}` remain on their existing paths.

## Ownership and boundary

The spans and static message borrow parser source storage. No evaluator or
program ABI changes are involved. General parser recovery and additional
diagnostic cardinalities remain outside this bounded payload until separately
contracted.
