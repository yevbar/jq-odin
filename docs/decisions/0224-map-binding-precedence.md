# Decision 0224: map binding call precedence

The `map` call argument is parsed with the ordinary binding precedence while
retaining the call's closing delimiter. This keeps `expr as $name | body` inside
`map(...)` instead of escaping to the surrounding query. The change is parser
only and preserves the evaluator's lexical binding contract.
