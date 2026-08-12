# Bounded static object-field numeric assignment

This shard covers only `.field = NUMBER` when the input object already has the
named field. The append-only AST/opcode carries the field name and numeric
spelling as owned text operands, and the evaluator clones the input object before
replacing the member. Nested paths, missing-field construction, array indexing,
dynamic keys, generators, negative literals, and other assignment operators
remain deferred.
