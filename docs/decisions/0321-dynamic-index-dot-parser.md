# Immediate identity dynamic-index key

The parser accepts an immediate `.` as the key of a postfix dynamic index,
reusing the existing `Index` instruction ABI and evaluator continuation. This
covers `[][.]` and `[1][.]` without admitting general filter-valued keys or
arithmetic expressions such as `[1][. + 0]`; those remain a separate language
contract. Numeric and existing dynamic index forms are unchanged.

Evidence: `src/syntax/parser.odin` recognizes the dot token only inside the
dynamic bracket branch, emits an `Identity` key node, and still leaves the
standalone postfix-dot diagnostic guard intact. `compat/dynamic-index-dot.jq.test`
matches the pinned jq oracle for the bounded forms.
