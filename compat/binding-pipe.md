# Pipe/binding precedence compatibility shard

The parser now treats `input | expr as $name | body` as a pipe whose right
child is the binding, matching jq's low-precedence `as` grammar. This keeps
the binding body's input equal to the piped value and preserves the Cartesian
stream from a nested `.[]`.

The focused case is derived from `upstream/jq/tests/jq.test:716`.
