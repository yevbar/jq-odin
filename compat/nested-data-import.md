# Nested data import aliases

Qualified data aliases (`$d::d`) now preserve the imported array stream, and
object shorthand aliases (`{$a, $b}`) lower to explicit key/value entries.
Oracle source: `upstream/jq/tests/jq.test:1874-1881`.
