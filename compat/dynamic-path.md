# Dynamic path generator

This shard covers the bounded dynamic path contract implemented by the
evaluator: `path(.foo[])` enumerates the immediate array indexes or object
keys below a static prefix. The evaluator materializes those path values in an
owned stream and resumes one output at a time, preserving jq's generator
cardinality. General dynamic filters, slices, and comma-index paths remain
separate contracts.
