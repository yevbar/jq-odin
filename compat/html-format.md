# `@html` compatibility shard

The escaping oracle is anchored by `upstream/jq/tests/jq.test:102-104`.  This
shard covers the zero-argument `@html` format filter.  The evaluator
stringifies scalar inputs using the existing format-filter coercion contract,
then escapes the five HTML-sensitive ASCII characters (`&`, `<`, `>`, `'`, and
`"`) as `&amp;`, `&lt;`, `&gt;`, `&apos;`, and `&quot;`.  Other bytes, including
valid UTF-8, pass through unchanged.

The bounded format-string form now accepts literal fragments and interpolation
queries, including multiple interpolations. Literal fragments are copied
without formatting and each interpolation result is passed through `@html`
before the existing string-addition path concatenates the segments. Ordinary
jq string interpolation is covered separately by `string-interpolation`; format
strings for directives other than `@html` remain deferred.
