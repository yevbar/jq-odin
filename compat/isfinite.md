# `isfinite` compatibility shard

The zero-argument `isfinite` predicate emits true for finite numeric inputs
and false for infinities, NaN, and non-number values. This bounded shard covers
a finite number; special-number and type-negative cases are exercised by the
Odin unit test and remain tracked for broader catalog coverage.

The jq oracle defines the predicate in `upstream/jq/src/builtin.jq:53`.
Run `tools/compat/jq_compat.py` against the pinned oracle and candidate;
expected result is one selected case and one passing case.
