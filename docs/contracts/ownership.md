# Ownership vocabulary

Odin does not enforce borrowing, moves, or reference counting. Until a more
specific accepted decision replaces these rules:

- procedure parameters are borrowed for the duration of the call by default;
- `clone_*` returns independently owned storage;
- `take_*` transfers ownership and leaves the source in a documented inert
  state;
- `destroy_*` releases a complete owned value and makes repeated use invalid;
- returned strings and slices must document the owner of their backing memory;
- values that escape a call receive an explicit allocator or belong to an
  explicitly named arena;
- `context.temp_allocator` data never escapes the declared temporary phase;
- pointers to dynamic-array elements do not survive possible growth;
- pointers to map elements do not survive map mutation;
- JSON `null` is an explicit logical value, never the nil state of an Odin
  union.

Every source field that owns, borrows, aliases, or reference-counts memory must
be classified in the appropriate `evidence/ownership/*.tsv` shard before its
translation is treated as complete.

