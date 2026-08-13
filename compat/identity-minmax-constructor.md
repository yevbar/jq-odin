# Identity-key min/max constructor

The exact identity-key forms `min_by(.)` and `max_by(.)` have the same jq
ordering semantics as `min` and `max`. The driver lowers the canonical
constructor to existing operand-free builtins, avoiding a new key-materializing
opcode. General key filters remain unsupported.
