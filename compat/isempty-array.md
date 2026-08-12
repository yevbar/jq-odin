# `isempty` literal arrays

The bounded `isempty` implementation now accepts literal arrays and returns
`false`, matching jq's value-producing array semantics. Generator children and
dynamic expressions remain covered by the broader iterator work.

Oracle evidence: `upstream/jq/src/builtin.jq:187` and
`upstream/jq/tests/jq.test:2097-2101`.
