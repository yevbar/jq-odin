# Predicate path continuation

The bounded path slice supports `path(.[] | select(. > N))` for numeric array
inputs, emitting only indices whose values are greater than the literal bound.
