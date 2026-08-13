# Decision 0265: bounded static path forks

`path(.foo[0,1])` is represented by the existing comma/Fork AST and program
instruction. The evaluator now materializes each literal path branch in source
order and feeds the existing path continuation. This deliberately excludes
dynamic filters, slices, and computed indexes, which require a general path
generator contract.

Evidence: `upstream/jq/tests/jq.test:1101-1104`.
