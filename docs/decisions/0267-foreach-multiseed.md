# Multi-seed foreach replay

`foreach .[] as $x (0, 1; . + $x)` must emit `1, 3, 2, 4`: jq evaluates the
initializer as a generator, then replays the full input generator for each
seed in left-to-right order (`upstream/jq/tests/jq.test:2496-2503`).

The parser now keeps commas live in the foreach initializer. The evaluator
materializes a literal seed stream from `Fork`/`Sequence` branches and replays
the existing bounded array/range foreach update loop for each seed. This is a
vertical compatibility slice; arbitrary initializer/update generators remain
deferred until the shared continuation contract is generalized.
