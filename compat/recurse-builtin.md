# Zero-argument recurse builtin

The named zero-argument `recurse` builtin is equivalent to jq's standalone
recursive-descent spelling `..`: it emits the current value, then visits array
elements or object values in preorder depth-first order. This shard keeps the
existing operand-free `Recurse` instruction and does not imply support for
parameterized `recurse(f)` calls.
