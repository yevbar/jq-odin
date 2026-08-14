# Decision 0319: compose bounded root iterator updates

The parser consumes a comma immediately following a bounded root `.[]`
compound update and recursively parses the remaining arms, lowering the result
to the existing `Comma` sequence node. No new evaluator or path-update ABI is
introduced: each arm remains the previously validated static iterator update,
and jq's comma semantics re-evaluate every arm against the original input.

This is intentionally limited to the five numeric compound operators and does
not generalize arbitrary path-update streams or generator-valued assignments.
