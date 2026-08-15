# Bounded static `del` path products

Static `del` now accepts a path product of field/index selector streams, such
as `del((.foo,.bar,.baz) | .[2,3,0])`. The parser materializes the Cartesian
product into the existing `Delpaths` path-array ABI and orders non-negative
numeric selector leaves descending so deletion uses original coordinates.

Only literal fields and non-negative integer indexes are admitted. Dynamic
keys, slices, generator-valued path expressions, and filter-valued updates
remain deferred to the general path continuation contract. The full
multi-expression jq.test:1168 probe and `compat/static-del.jq.test` provide
the evidence.
