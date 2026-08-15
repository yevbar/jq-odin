# Bounded nested static `del` paths

The static deletion lowering now recursively materializes field/index chains
such as `.foo.bar[0]` into the existing literal `Delpaths` path-array ABI.
This is limited to static field names and numeric indexes; selector pipelines,
slices, computed keys, and filter-valued updates remain outside the contract.

Focused evidence is in `compat/static-del.jq.test`; the nested case is checked
against jq 1.8.1 with copy-on-write output and key preservation.
