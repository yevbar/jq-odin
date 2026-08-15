# Decision 0336: bounded static field deletion update

The root static update `.foo |= empty` is a genuine path mutation: jq removes
the `foo` member when present, leaves missing fields and null roots unchanged,
and raises `Cannot index ... with string "foo"` for arrays and numbers. The
parser now lowers only this exact empty RHS to `Static_Field_Delete`; the
compiler stores one owned field-name operand and the evaluator removes the
member with the existing object ownership APIs.

The opcode is intentionally separate from `.foo |= .?`: an empty RHS means
deletion, while optional identity materializes a missing null field. Generator
RHS filters, nested paths, dynamic keys, and multi-path updates remain outside
this bounded continuation contract and continue to reject at parse time.

Evidence: pinned jq 1.8.1 probes in `compat/static-field-delete.jq.test` and
the near-match rejection `.foo |= .[]`. Focused ownership review covers
copy-on-write object mutation, key/value destruction, and null no-op handling.
