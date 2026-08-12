# Array destructuring compatibility shard

This shard covers the bounded two-slot array pattern `as [$a, $b]`. The
parser lowers each positional binding to the existing lexical `Binding`
contract and a static numeric index. The bounded slice applies to a direct
identity producer (`. as [...]`); iterator-fed patterns, object patterns,
nested patterns, and optional (`?//`) alternatives remain outside this
contract.
