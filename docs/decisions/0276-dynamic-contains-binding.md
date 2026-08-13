# Decision 0276: dynamic `contains` binding operand

The existing `Contains` instruction already owns one child instruction, but
the parser previously admitted only literal child forms and the evaluator
materialized every child as a literal. jq cases 1615 and 1619 use
`contains($needle)` where `$needle` is produced by an enclosing `as` binding.

We preserve the existing instruction ABI and admit only a `Variable` child for
this bounded case. The evaluator resolves that variable from the current
binding frame, clones the owned value, and reuses `contains_result`. General
filter-valued children still require a resumable child-evaluation contract and
are intentionally not broadened here.
