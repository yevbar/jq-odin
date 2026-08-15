# Decision 0338: nested static index filter-update boundary

The current root `Static_Field_Update` continuation cannot safely implement
`.foo[0] |= FILTER` by composition. A nested update needs a distinct
field-plus-index continuation that runs the RHS against the selected element,
cancels after the first output, and propagates empty cardinality according to
the path state.

Pinned jq 1.8.1 probes demonstrate the state-dependent contract:

```
{"foo":[2,3]} | .foo[0] |= empty  # {"foo":[3]}
{"foo":[]}   | .foo[0] |= empty  # {"foo":[]}
{}            | .foo[0] |= empty  # {}
null          | .foo[0] |= empty  # null
{"foo":[]}   | .foo[0] |= .+1    # {"foo":[1]}
{}            | .foo[0] |= .+1    # {"foo":[1]}
null          | .foo[0] |= .+1    # {"foo":[1]}
```

An outer `Static_Field_Update` can only treat an empty child stream as field
deletion; it cannot distinguish an existing empty array (which must remain)
from a missing/null intermediate (which must remain absent/null). The existing
`Static_Index_Set_Number` opcode is scalar-literal assignment and has no RHS
filter continuation. Supporting this slice therefore requires a new nested
path opcode, frame phases, and ownership/error handling. Arbitrary dynamic or
deeper paths remain outside this boundary.
