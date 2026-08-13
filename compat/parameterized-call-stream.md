# Parameterized call stream arguments

Top-level parameterized definitions are routed through the module expander.
Filter-valued parameters preserve comma-produced stream cardinality, matching
jq's `id(1, 2)` behavior.
