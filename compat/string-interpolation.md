# Ordinary string interpolation compatibility shard

This shard covers literal double-quoted filters containing one or more
`\(query)` segments. Literal fragments are decoded without formatting, while
each query result is converted with jq-compatible `tostring` behavior and then
concatenated through string addition. A query that emits multiple values emits
one completed string per value.

The slice deliberately excludes dynamic format operators, format directives
other than the already-supported bounded `@html "..."` form, interpolation in
quoted object keys and quoted field names, assignment, and new interpolation-
specific diagnostic wording.
