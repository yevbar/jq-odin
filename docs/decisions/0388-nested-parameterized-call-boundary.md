# Decision 0388: jq.test:864 remains beyond the one-formal call slice

## Audit

The focused oracle shard `compat/nested-definition-calls.jq.test` exercises
the deferred 864 case:

```jq
[[20,10][1,0] as $x | def f: (100,200) as $y |
  def g: [$x + $y, .]; . + $x | g;
  f[0] | [f][0][1] | f]
```

Its expected stream contains eight arrays, beginning
`[110.0,130.0]`, `[210.0,130.0]`, and ending `[220.0,260.0]` (full oracle
output is recorded in the fixture). This requires nested zero-argument
definitions inside a parameterized body, two lexical bindings (`$x`, `$y`),
and repeated generator entry through `f`.

The current runtime phase only activates a direct `Call` whose body is the
single `Parameter_Reference` opcode. The evaluator retains one argument edge
on that body frame (`src/eval/evaluator.odin:8886-8908`), while ordinary
`Binding` frames expose only one mutable value to `variable_result`
(`src/eval/evaluator.odin:1082-1105`). A composed body containing bindings,
nested definitions, and a call cannot be routed through that direct marker
without losing declaration-time scope or generator continuation state.

## Boundary

Do not broaden the driver guard or textually expand this case. A sound phase
needs immutable callable entries carrying lexical parent/definition ordinal,
per-call argument-filter closures, and evaluator frames that preserve each
binding environment while nested generators resume. The existing direct
one-formal fixture remains supported; 864 is deferred until that closure-frame
ABI is implemented and tested against all eight outputs.

