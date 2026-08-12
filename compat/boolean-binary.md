# Boolean binary operators

The append-only `Or` and `And` opcodes implement jq truthiness (`null` and
`false` are falsey; all other values are truthy) using the existing binary
continuation and owned value cleanup.

Evidence: `upstream/jq/tests/jq.test:1472`.
