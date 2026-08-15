# Static field deletion update

This shard implements the exact root static update `.foo |= empty` through a
dedicated AST/program/evaluator opcode. Existing fields are removed, missing
fields and null roots remain unchanged, and non-object/non-null roots retain
jq's typed string-index diagnostics. Generator-valued RHS filters such as
`.foo |= .[]` remain rejected by the parser; this slice does not broaden the
general path-update continuation contract.
