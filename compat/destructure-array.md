# Array destructuring compatibility shard

This shard covers the bounded two-slot array pattern `as [$a, $b]`. The
parser lowers each positional binding to the existing lexical `Binding`
contract and a static numeric index. The bounded slice applies to a direct
producer, including an iterator-fed producer (`.[] as [...]`). Nested
patterns, object patterns, and optional (`?//`) alternatives remain outside
this contract.
