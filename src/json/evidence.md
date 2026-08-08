# JSON streaming evidence

- `upstream/jq/src/jv_parse.c:722-752` retains unconsumed parser-buffer bytes
  after a completed value, establishing the absolute-offset pull boundary.
- `upstream/jq/src/jv_parse.c:767-820` returns one completed value per parser
  pull and reports parse failure independently from end-of-input.
- `upstream/jq/src/util.c:395-444` repeatedly feeds input buffers to the parser
  and emits values in source order; newline splitting is not the framing rule.

The JSON package exposes this as `parse_next_value`: the input is borrowed for
the call, each successful `value.Value` is allocator-owned by the caller, and
`next` is the absolute byte offset for the following pull. `done` distinguishes
trailing whitespace from a parse error.
