# Bounded sort_by field

The driver lowers whole-filter `sort_by(.field)` calls into existing
`map([.field,.]) | sort | map(.[1])` operations. This preserves jq's stable
scalar-key ordering for the bounded static-field form; general key filters and
group/min/max variants require a dedicated materialization opcode.
