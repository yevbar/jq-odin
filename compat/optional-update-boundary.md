# Optional update boundary probes

Pinned jq 1.8.1 probes:

```text
{}                  | try (.foo |= .?) catch .  -> {"foo":null}
null                | try (.foo |= .?) catch .  -> {"foo":null}
{"foo":"bar"}    | try (.foo |= .?) catch .  -> {"foo":"bar"}
[1]                 | try (.foo |= .?) catch .  -> "Cannot index array with string \"foo\""
["1","x",null,2]  | .[] |= try tonumber    -> [1,2]
```

The candidate currently rejects both filters before evaluation. `.foo |= .?`
cannot be lowered to `Dynamic_Field_Set` identity: that opcode evaluates an
identity RHS against the whole input, while update RHS filters must run against
the selected field (and create a missing field as null). `.[] |= try tonumber`
requires resumable per-element RHS streams, error suppression, and deletion of
elements whose RHS is empty.
