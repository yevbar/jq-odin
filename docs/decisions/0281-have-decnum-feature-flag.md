# Decision 0281: lower have_decnum to the active numeric feature flag

Recognize the zero-argument identifier `have_decnum` as Boolean `true` in the
parser. No runtime opcode or numeric representation changes are needed: the
current value layer already preserves jq-compatible decimal-backed spellings.
