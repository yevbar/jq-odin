# Decision 0384: formal parameters are filter arguments

## Status

The attempted parameter-name value-binding ABI was rejected after differential
testing. jq formal parameters denote filter closures, not values stored under a
variable name in the callee frame.

## Oracle evidence

With null input, jq 1.8.1 distinguishes:

```jq
2000 as $x | def f(x): 1 as $x | x; f($x)
```

which emits `2000`, from:

```jq
2000 as $x | def f(x): 1 as $x | $x; f($x)
```

which emits `1`. The exact jq.test:864 fixture emits
`[1,100,2100,100,2100]` and requires this distinction through nested calls and
array construction.

## ABI boundary

`Node.Call`/`Program.Call` must retain a formal filter reference and argument
closure root, not merely a parameter-name text operand. Evaluator activation
must invoke that filter against the callee input while lexical `$` variables
remain ordinary Binding-frame lookups. A future phase should introduce an
explicit parameter-reference/closure operand and test both probes before
routing nested definitions away from the module bridge.
