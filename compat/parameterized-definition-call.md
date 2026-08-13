# Parameterized definition calls

This shard covers filter-valued parameters, multi-argument calls, generator
arguments, and `$` value parameters. The driver routes parameterized
definitions through the module expansion bridge while retaining the direct
parser/Call path for zero-argument definitions.

Oracle source: `upstream/jq/tests/jq.test:785-787,851-856,868-871`.
