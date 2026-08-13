# Bounded nested pick(first)

The exact whole-filter `pick(first|first)` form lowers to
`.[0:1] | map(.[0:1])`, preserving jq's nested array result.
