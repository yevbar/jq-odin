# `try`/`catch` precedence compatibility shard

The parser now treats an unparenthesized catch filter as an atomic term at the
surrounding binary precedence. Parenthesized catch expressions still parse
their own binary operators. This matches jq's `try 2 catch 3 + 4` behavior.

The primary regression is `upstream/jq/tests/jq.test:1456`.
