# Decision 0106: simple object literal `bsearch`

Extend the numeric literal `bsearch` slice to simple object literals with
literal scalar members. The evaluator reconstructs the owned object needle
from compiled key/value operands, then reuses the existing recursive value
ordering comparator. Multi-needle generators, dynamic arguments, nested
object expressions, and non-array diagnostics remain deferred from
`upstream/jq/tests/jq.test:1797`.
