# Decision 0159: preserve field-only iterator mode with range

The initial literal `range` integration narrowed the evaluator's resumed
iterator validation to normal-mode frames, which regressed existing `.[]`
field iterators. Restore `Field_Only` for `Field` while allowing `Range` in
normal mode. This keeps the range stream contract isolated without changing
existing iterator ownership or cardinality behavior.

Evidence: the full pinned catalog fell from 172/522 to 142/522 with the
initial condition; after this fix it reports 175/522, including the three
newly passing literal-range cases. Package/build checks remain green.
