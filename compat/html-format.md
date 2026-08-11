# `@html` compatibility shard

The escaping oracle is anchored by `upstream/jq/tests/jq.test:102-104`.  This
shard covers the zero-argument `@html` format filter.  The evaluator
stringifies scalar inputs using the existing format-filter coercion contract,
then escapes the five HTML-sensitive ASCII characters (`&`, `<`, `>`, `'`, and
`"`) as `&amp;`, `&lt;`, `&gt;`, `&apos;`, and `&quot;`.  Other bytes, including
valid UTF-8, pass through unchanged.

The format-argument/interpolation form (`@html "..."`) and other jq format
filters remain outside this lane; they require a separate parser/program
contract and are intentionally not claimed by this shard.
